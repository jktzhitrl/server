// NEXORA Sampler – Audio-Engine (Portierung von NexoraCore/Engine/SamplerEngine.swift).
// Läuft im AudioWorklet (Echtzeit) sowie direkt für Offline-Export und Tests.
// Im Betrieb keine Allokationen: Stimmen, Busse und Effektpuffer werden einmalig angelegt.

import {
  clamp, semitonesToRatio, balanceGains, hermite, distort, SmoothedValue, StateVariableFilter, ADSREnvelope,
  LFO, Bitcrusher, Compressor, ThreeBandEQ, StereoDelay, Reverb, VibratoProcessor
} from './dsp.js';
import { defaultPadSettings, defaultMaster, effectiveDelaySeconds, swingDelay, fillMotion, PARAMS, TRACKS, MAX_STEPS, PATTERN_SLOTS, SONG_MAX_LENGTH } from './model.js';

export const PAD_COUNT = 16;
export const MAX_POLYPHONY = 64;
export const PHYSICAL_VOICES = MAX_POLYPHONY + 16;
const MAX_CHUNK = 512;

/** Sample-Daten: { left: Float32Array, right: Float32Array (oder === left), sampleRate, frameCount } */
function readFrame(s, pos, out) {
  const n = s.frameCount;
  const i = Math.floor(pos);
  const t = pos - i;
  const i0 = Math.min(Math.max(i, 0), n - 1);
  const im1 = Math.max(i0 - 1, 0), i1 = Math.min(i0 + 1, n - 1), i2 = Math.min(i0 + 2, n - 1);
  const L = s.left, R = s.right;
  out[0] = hermite(L[im1], L[i0], L[i1], L[i2], t);
  out[1] = R === L ? out[0] : hermite(R[im1], R[i0], R[i1], R[i2], t);
}

function wrapPos(p, rStart, rEnd, rLen) {
  if (p >= rEnd) p = rStart + ((p - rEnd) % rLen);
  if (p < rStart) p = rEnd - ((rStart - p) % rLen);
  return p;
}

class Voice {
  constructor() {
    this.active = false; this.isPreview = false; this.pad = 0; this.sample = null;
    this.position = 0; this.readHead = 0;
    this.g0Start = 0; this.g0Phase = 0; this.g1Start = 0; this.g1Phase = -0.5; this.firstGrain = true;
    this.env = new ADSREnvelope(); this.filter = new StateVariableFilter(); this.crusher = new Bitcrusher();
    this.lfo = new LFO(); this.gain = new SmoothedValue(0);
    this.velocityGain = 1; this.fadeGain = 1; this.fadeStep = 0; this.age = 0;
    this.fromSequencer = false; this.released = false; this.level = 0; this.transpose = 0;
  }
  get isFading() { return this.fadeStep > 0; }
}

/** Sample-genauer Step-Sequencer (Zeiten in 16tel-Schritten seit Start). */
class SequencerClock {
  constructor() {
    this.state = 'stopped'; this.position = 0; this.bpm = 120; this.swing = 50;
    this.muteMask = 0; this.soloMask = 0; this.metronome = false;
    this.patterns = new Array(PATTERN_SLOTS).fill(null);
    this.currentSlot = 0; this.queuedSlot = -1; this.patternStartStep = 0; this.nextStepToQueue = 0;
    // Die Planung läuft bis zu einem Schritt voraus; hörbar ist das alte Pattern bis switchStep.
    this.previousSlot = 0; this.previousStartStep = 0; this.previousSongIndex = 0; this.switchStep = -Infinity;
    /** Song-Modus: Kette der Slots oder null */
    this.song = null; this.songIndex = 0;
    this.capacity = 1024;
    this.evTime = new Float64Array(this.capacity); this.evKind = new Uint8Array(this.capacity);
    this.evPad = new Int8Array(this.capacity); this.evVel = new Float32Array(this.capacity);
    this.count = 0;
    this.loc = { slot: 0, step: 0, fraction: 0, length: 16, songIndex: 0 };
  }
  _markSwitch(step) {
    this.previousSlot = this.currentSlot; this.previousStartStep = this.patternStartStep;
    this.previousSongIndex = this.songIndex; this.switchStep = step; this.patternStartStep = step;
  }
  setSong(chain) {
    const old = this.song;
    this.song = chain && chain.length ? chain : null;
    if (this.song) {
      this.queuedSlot = -1;
      if (this.state === 'stopped') { this.songIndex = 0; this.currentSlot = this.song[0]; }
      else if (!old || this.songIndex >= this.song.length || this.song[Math.max(this.songIndex, 0)] !== this.currentSlot) {
        this.songIndex = this.song.indexOf(this.currentSlot);
      }
    }
  }
  selectPattern(slot, immediately) {
    if (slot < 0 || slot >= PATTERN_SLOTS) return;
    if (this.state !== 'playing' || immediately) {
      this._markSwitch(this.state === 'playing' ? this.nextStepToQueue : Math.floor(this.position));
      this.currentSlot = slot; this.queuedSlot = -1;
      if (this.song) { const i = this.song.indexOf(slot); if (i >= 0) this.songIndex = i; }
    } else {
      this.queuedSlot = slot === this.currentSlot ? -1 : slot;
    }
  }
  play() {
    if (this.state === 'stopped') {
      this.position = 0; this.nextStepToQueue = 0; this.patternStartStep = 0; this.switchStep = -Infinity; this.count = 0;
      if (this.song) { this.songIndex = 0; this.currentSlot = this.song[0]; this.queuedSlot = -1; }
      else if (this.queuedSlot >= 0) { this.currentSlot = this.queuedSlot; this.queuedSlot = -1; }
    }
    this.state = 'playing';
  }
  pause() { if (this.state === 'playing') this.state = 'paused'; }
  stop() {
    this.state = 'stopped'; this.position = 0; this.nextStepToQueue = 0; this.patternStartStep = 0; this.switchStep = -Infinity; this.count = 0;
    if (this.song) { this.songIndex = 0; this.currentSlot = this.song[0]; }
  }
  patternLength(slot) { return Math.max(this.patterns[slot]?.length ?? 16, 1); }
  /** Hörbares Pattern, Schritt und Bruchteil an einer Position (ohne Allokation). */
  locate(pos) {
    const old = pos < this.switchStep;
    const slot = old ? this.previousSlot : this.currentSlot;
    const start = old ? this.previousStartStep : this.patternStartStep;
    const len = this.patternLength(slot);
    const rel = pos - start;
    const whole = Math.floor(rel);
    const l = this.loc;
    l.slot = slot; l.length = len; l.step = ((whole % len) + len) % len; l.fraction = rel - whole;
    l.songIndex = old ? this.previousSongIndex : this.songIndex;
    return l;
  }
  stepsPerSample(sr) { return (this.bpm / 60) * 4 / sr; }
  get currentLength() { return this.patternLength(this.currentSlot); }
  get displayStep() { return this.locate(this.position).step; }
  schedule(horizon) {
    while (this.nextStepToQueue - 0.5 < horizon) { this._queueStep(this.nextStepToQueue); this.nextStepToQueue++; }
  }
  _push(time, kind, pad, vel) {
    if (this.count >= this.capacity) return;
    const i = this.count++;
    this.evTime[i] = time; this.evKind[i] = kind; this.evPad[i] = pad; this.evVel[i] = vel;
  }
  _queueStep(k) {
    let len = this.currentLength;
    if ((k - this.patternStartStep) % len === 0) {
      if (this.song) {
        // Song: am Ende jedes Patterns zum nächsten Ketteneintrag (am Ende wieder von vorn).
        if (k > this.patternStartStep || this.songIndex < 0) {
          const next = this.songIndex + 1 >= this.song.length ? 0 : this.songIndex + 1;
          this._markSwitch(k);
          this.songIndex = next; this.currentSlot = this.song[next];
          len = this.currentLength;
        }
      } else if (this.queuedSlot >= 0) {
        this._markSwitch(k);
        this.currentSlot = this.queuedSlot; this.queuedSlot = -1;
        len = this.currentLength;
      }
    }
    const sp = (((k - this.patternStartStep) % len) + len) % len;
    const sd = swingDelay(k, this.swing);
    if (this.metronome && sp % 4 === 0) this._push(k, 2, sp === 0 ? 1 : 0, 1);
    const p = this.patterns[this.currentSlot];
    if (!p) return;
    const solo = this.soloMask !== 0;
    for (let t = 0; t < TRACKS; t++) {
      const bit = 1 << t;
      if (this.muteMask & bit) continue;
      if (solo && !(this.soloMask & bit)) continue;
      const st = p.steps[t * MAX_STEPS + sp];
      if (!st.active) continue;
      const time = k + sd + st.offset;
      this._push(time, 0, t, st.velocity);
      this._push(time + p.gates[t], 1, t, 0);
    }
  }
  nextEventTime() {
    if (!this.count) return null;
    let t = this.evTime[0];
    for (let i = 1; i < this.count; i++) if (this.evTime[i] < t) t = this.evTime[i];
    return t;
  }
  /** Entnimmt das früheste fällige Ereignis in `out` ({time, kind, pad, velocity}); false, wenn keines fällig ist. */
  popDue(time, out) {
    let best = -1, bestTime = Infinity;
    for (let i = 0; i < this.count; i++) {
      if (this.evTime[i] <= time + 1e-9 && this.evTime[i] < bestTime) { best = i; bestTime = this.evTime[i]; }
    }
    if (best < 0) return false;
    out.time = this.evTime[best]; out.kind = this.evKind[best]; out.pad = this.evPad[best]; out.velocity = this.evVel[best];
    const last = --this.count;
    this.evTime[best] = this.evTime[last]; this.evKind[best] = this.evKind[last];
    this.evPad[best] = this.evPad[last]; this.evVel[best] = this.evVel[last];
    return true;
  }
  discardPendingNotes() {
    let i = 0;
    while (i < this.count) {
      if (this.evKind[i] !== 1) {
        const last = --this.count;
        this.evTime[i] = this.evTime[last]; this.evKind[i] = this.evKind[last];
        this.evPad[i] = this.evPad[last]; this.evVel[i] = this.evVel[last];
      } else i++;
    }
  }
  advance(steps) { if (this.state === 'playing') this.position += steps; }
}

/** Kompakte Pattern-Kopie für den Audio-Thread (inkl. vorberechneter Motion-Spuren). */
export function patternSnapshot(p) {
  const steps = new Array(TRACKS * MAX_STEPS);
  for (let t = 0; t < TRACKS; t++) for (let s = 0; s < MAX_STEPS; s++) {
    const st = p.steps[t][s];
    steps[t * MAX_STEPS + s] = { active: !!st.active, velocity: st.velocity, offset: st.offset };
  }
  const length = Math.max(1, Math.min(p.length, MAX_STEPS));
  const motion = [];
  let motionPadMask = 0, hasMasterMotion = false;
  for (const lane of p.motion ?? []) {
    const spec = PARAMS[lane.parameter];
    if (!spec || !(spec.pad || spec.master)) continue;
    const { hold, smooth } = fillMotion(lane.values.slice(0, length));
    if (!hold.length) continue;
    const pad = spec.pad ? lane.pad : -1;
    motion.push({ key: spec.pad ?? spec.master, pad, hold: Float64Array.from(hold), smooth: Float64Array.from(smooth), last: NaN });
    if (pad >= 0) motionPadMask |= 1 << pad; else hasMasterMotion = true;
  }
  return { length, steps, gates: p.gates.slice(0, TRACKS), motion, motionPadMask, hasMasterMotion };
}

export class SamplerEngine {
  constructor(sampleRate) {
    this.sampleRate = sampleRate;
    this.voices = Array.from({ length: PHYSICAL_VOICES }, () => new Voice());
    this.previewVoice = new Voice();
    this.voiceCounter = 0;
    /** Wirksame Pad-Einstellungen (inkl. Motion) und die von der Oberfläche gesetzten Grundwerte */
    this.padSettings = Array.from({ length: PAD_COUNT }, () => defaultPadSettings());
    this.basePadSettings = Array.from({ length: PAD_COUNT }, () => defaultPadSettings());
    this.padSamples = new Array(PAD_COUNT).fill(null);
    this.padLevels = new Float32Array(PAD_COUNT + 1);
    this.padTriggers = new Uint32Array(PAD_COUNT);
    this.lastManualHit = new Float64Array(PAD_COUNT).fill(-1000);
    this.previewSettings = { ...defaultPadSettings(), volume: 1, reverbSend: 0, delaySend: 0, velocitySensitivity: 0, release: 0.01 };
    this.previewGain = 1;
    this.master = defaultMaster();
    this.baseMaster = defaultMaster();
    this.motionMaster = defaultMaster();
    this.motionMode = 'hold';
    this.motionTouchedPads = 0; this.motionTouchedMaster = false;
    this.engineSettings = { polyphony: 32, stealMode: 'oldest' };
    this.isRecording = false;
    const buf = () => new Float32Array(MAX_CHUNK);
    this.dryL = buf(); this.dryR = buf(); this.revL = buf(); this.revR = buf(); this.dlyL = buf(); this.dlyR = buf();
    this.wetRevL = buf(); this.wetRevR = buf(); this.wetDlyL = buf(); this.wetDlyR = buf(); this.postL = buf(); this.postR = buf();
    this.allBuffers = [this.dryL, this.dryR, this.revL, this.revR, this.dlyL, this.dlyR, this.wetRevL, this.wetRevR, this.wetDlyL, this.wetDlyR, this.postL, this.postR];
    this.delay = new StereoDelay(sampleRate);
    this.reverb = new Reverb(sampleRate);
    this.vibrato = new VibratoProcessor(sampleRate);
    this.masterFilter = new StateVariableFilter();
    this.masterCrusher = new Bitcrusher();
    this.eq = new ThreeBandEQ(sampleRate);
    this.comp = new Compressor(sampleRate);
    this.modLFO = new LFO();
    this.masterVolume = new SmoothedValue(0.64, 0.02, sampleRate);
    this.filterWet = new SmoothedValue(0, 0.01, sampleRate);
    this.cutoffLog = new SmoothedValue(Math.log2(20000), 0.03, sampleRate / 16);
    this.delayMix = new SmoothedValue(0, 0.02, sampleRate);
    this.reverbMix = new SmoothedValue(0, 0.02, sampleRate);
    this.lastFilterMode = 'lowPass';
    this.primed = false;
    this.click = { remaining: 0, phase: 0, freq: 1000, length: 1 };
    this.seq = new SequencerClock();
    this.ev = { time: 0, kind: 0, pad: 0, velocity: 0 };
    this.frame = new Float32Array(2);
    this.panTmp = new Float32Array(2);
    this.recordedHits = [];
    this.status = {
      currentStep: 0, transport: 'stopped', activeVoices: 0, peakL: 0, peakR: 0, currentPattern: 0, queuedPattern: -1,
      position: 0, gainReduction: 0, songIndex: -1, padLevels: new Float32Array(PAD_COUNT + 1), padTriggers: new Uint32Array(PAD_COUNT)
    };
    this.applyMaster(this.master);
  }

  // ------------------------------------------------------------ Befehle

  noteOn(pad, velocity) {
    if (this.seq.state === 'playing' && this.isRecording && pad >= 0 && pad < PAD_COUNT) this._recordHit(pad, velocity);
    this._startVoice(pad, velocity, false, 0);
  }
  noteOnTransposed(pad, velocity, semitones) { this._startVoice(pad, velocity, false, semitones); }
  noteOff(pad) { this._releasePad(pad, false); }
  allNotesOff() { for (const v of this.voices) if (v.active) this._beginFade(v, 0.01); }
  setSample(pad, sample) { if (pad >= 0 && pad < PAD_COUNT) this.padSamples[pad] = sample; }
  setPadSettings(pad, settings) {
    if (pad < 0 || pad >= PAD_COUNT) return;
    this.basePadSettings[pad] = { ...defaultPadSettings(), ...settings };
    this.padSettings[pad] = { ...this.basePadSettings[pad] };
  }
  setMaster(m) { this.baseMaster = { ...defaultMaster(), ...m }; this.applyMaster(this.baseMaster); }
  /** Song-Modus: Kette der Slots (Array) oder null */
  setSong(chain) {
    const c = Array.isArray(chain) ? chain.filter((x) => Number.isInteger(x) && x >= 0 && x < PATTERN_SLOTS).slice(0, SONG_MAX_LENGTH) : null;
    this.seq.setSong(c && c.length ? c : null);
  }
  setMotionMode(mode) {
    this.motionMode = ['off', 'hold', 'smooth'].includes(mode) ? mode : 'hold';
    if (this.motionMode === 'off') this._restoreMotion(true, 0, false);
  }
  setEngineSettings(s) {
    this.engineSettings = { polyphony: clamp(s.polyphony | 0, 1, MAX_POLYPHONY), stealMode: s.stealMode ?? 'oldest' };
    this._enforcePolyphony();
  }
  setPattern(slot, snapshot) { if (slot >= 0 && slot < PATTERN_SLOTS) this.seq.patterns[slot] = snapshot; }
  selectPattern(slot, immediately) { this.seq.selectPattern(slot, immediately); }
  setTempo(bpm, swing) { this.seq.bpm = clamp(bpm, 20, 400); this.seq.swing = clamp(swing, 50, 75); }
  setTrackStates(mutes, solos) { this.seq.muteMask = mutes; this.seq.soloMask = solos; }
  transport(cmd) {
    if (cmd === 'play') this.seq.play();
    else if (cmd === 'pause') { this.seq.pause(); this._releaseSequencerVoices(); this._restoreMotion(true, 0, false); }
    else if (cmd === 'stop') { this.seq.stop(); this._releaseSequencerVoices(); this._restoreMotion(true, 0, false); }
  }
  setRecording(on) { this.isRecording = !!on; }
  setMetronome(on) { this.seq.metronome = !!on; }
  preview(sample, gain = 1) {
    this.previewGain = gain;
    if (sample) {
      const v = this.previewVoice;
      this._resetVoice(v);
      v.active = true; v.isPreview = true; v.sample = sample; v.velocityGain = 1;
      v.gain.reset(gain); v.gain.coeff = Math.exp(-1 / (0.005 * this.sampleRate));
      v.env.configure(0.001, 1, 1, 0.01, this.sampleRate); v.env.noteOn();
    } else if (this.previewVoice.active) {
      this.previewVoice.fadeStep = 1 / (0.01 * this.sampleRate);
    }
  }

  /** Wendet eine Nachricht `{cmd, ...}` an (Worklet-Port, Offline-Renderer). */
  handle(m) {
    switch (m.cmd) {
      case 'noteOn': return this.noteOn(m.pad, m.velocity);
      case 'noteOnTransposed': return this.noteOnTransposed(m.pad, m.velocity, m.semitones);
      case 'noteOff': return this.noteOff(m.pad);
      case 'allNotesOff': return this.allNotesOff();
      case 'setSample': return this.setSample(m.pad, m.sample);
      case 'setPadSettings': return this.setPadSettings(m.pad, m.settings);
      case 'setMaster': return this.setMaster(m.master);
      case 'setEngineSettings': return this.setEngineSettings(m.settings);
      case 'setPattern': return this.setPattern(m.slot, m.pattern);
      case 'selectPattern': return this.selectPattern(m.slot, m.immediately);
      case 'setTempo': return this.setTempo(m.bpm, m.swing);
      case 'setTrackStates': return this.setTrackStates(m.mutes, m.solos);
      case 'transport': return this.transport(m.transport);
      case 'setRecording': return this.setRecording(m.on);
      case 'setMetronome': return this.setMetronome(m.on);
      case 'preview': return this.preview(m.sample, m.gain);
      case 'setSong': return this.setSong(m.chain);
      case 'setMotionMode': return this.setMotionMode(m.mode);
    }
  }

  applyMaster(s) {
    this.master = s;
    this.delay.feedback = s.delayFeedback; this.delay.pingPong = s.delayPingPong; this.delay.damping = s.delayDamping;
    this.reverb.roomSize = s.reverbSize; this.reverb.damping = s.reverbDamping; this.reverb.width = s.reverbWidth;
    this.eq.configure(s.eqLow, s.eqMid, s.eqHigh, s.eqMidFrequency);
    this.comp.threshold = s.compThreshold; this.comp.ratio = s.compRatio; this.comp.attack = s.compAttack;
    this.comp.release = s.compRelease; this.comp.makeup = s.compMakeup; this.comp.updateTimes();
  }

  // ------------------------------------------------------------ Rendering

  render(frames, outL, outR) {
    let done = 0;
    while (done < frames) {
      const n = Math.min(MAX_CHUNK, frames - done);
      this._renderChunk(n, outL, outR, done);
      done += n;
    }
    this._publishStatus(frames, outL, outR);
  }

  _renderChunk(n, outL, outR, outOffset) {
    for (const b of this.allBuffers) b.fill(0, 0, n);
    const seq = this.seq;
    let t = 0;
    while (t < n) {
      let chunk = n - t;
      const sps = seq.stepsPerSample(this.sampleRate);
      if (seq.state === 'playing') {
        seq.schedule(seq.position + 1);
        const motionActive = this._applyMotion();
        while (seq.popDue(seq.position, this.ev)) this._handleSeqEvent(this.ev);
        const next = seq.nextEventTime();
        if (next !== null) chunk = Math.min(chunk, Math.max(1, Math.ceil((next - seq.position) / sps)));
        chunk = Math.min(chunk, Math.max(1, Math.floor(0.5 / sps)));
        if (motionActive) {
          if (this.motionMode === 'smooth') chunk = Math.min(chunk, 64);
          else chunk = Math.min(chunk, Math.max(1, Math.ceil((Math.floor(seq.position) + 1 - seq.position) / sps)));
        }
      } else {
        while (seq.popDue(Infinity, this.ev)) if (this.ev.kind === 1) this._handleSeqEvent(this.ev);
      }
      for (const v of this.voices) if (v.active) this._renderVoice(v, t, chunk, false);
      if (this.previewVoice.active) this._renderVoice(this.previewVoice, t, chunk, true);
      this._renderClick(t, chunk);
      seq.advance(chunk * sps);
      t += chunk;
    }
    this._processMaster(n, outL, outR, outOffset);
  }

  _renderVoice(v, offset, count, isPreview) {
    const sample = v.sample;
    if (!sample) { v.active = false; return; }
    const s = isPreview ? this.previewSettings : this.padSettings[v.pad];
    const sr = this.sampleRate;
    const frames = sample.frameCount;
    const rStart = clamp(s.start, 0, 1) * frames;
    let rEnd = clamp(s.end, 0, 1) * frames;
    if (rEnd < rStart + 2) rEnd = Math.min(frames, rStart + 2);
    const rLen = Math.max(rEnd - rStart, 1);
    const dir = s.reverse ? -1 : 1;
    const looping = s.playMode === 'loop' && !isPreview;
    const stretch = s.pitchMode === 'timeStretch' && !isPreview;
    const srRatio = sample.sampleRate / sr;
    const baseSemis = s.pitch + s.fineTune / 100 + v.transpose;
    const speed = clamp(s.speed, 0.25, 4);
    let pitchRatio = semitonesToRatio(baseSemis);
    let rate = srRatio * pitchRatio * speed;
    let transposeRate = srRatio * pitchRatio;
    const headRate = srRatio * speed;
    const grainLen = 0.05 * sr, grainInc = 1 / grainLen;
    const lfoDepth = clamp(s.lfoDepth, 0, 1);
    const lfoActive = s.lfoTarget !== 'off' && lfoDepth > 0.0001;
    const baseCutoff = s.cutoff, reso = s.resonance;
    const envAmount = clamp(s.filterEnvAmount, -1, 1);
    const filterActive = s.filterMode !== 'off';
    const filterEnvActive = filterActive && Math.abs(envAmount) > 0.0001;
    let lfoOct = 0;
    v.filter.mode = s.filterMode;
    if (filterActive) v.filter.setParameters(baseCutoff, reso, sr);
    v.env.configure(s.attack, s.decay, s.sustain, s.release, sr);
    v.gain.target = s.volume * v.velocityGain * (isPreview ? this.previewGain : 1);
    const pan = balanceGains(s.pan, this.panTmp);
    let panL = pan[0], panR = pan[1];
    let tremolo = 1;
    const revSend = s.reverbSend, dlySend = s.delaySend;
    const drive = s.insertFXOn ? s.drive : 0;
    const bits = s.insertFXOn ? s.crushBits : 16;
    const ds = s.insertFXOn ? s.crushDownsample : 1;
    const crushActive = bits < 15.99 || ds > 1.001;
    const dryL = isPreview ? this.postL : this.dryL, dryR = isPreview ? this.postR : this.dryR;
    const fr = this.frame;
    let finished = false, peak = 0;
    for (let i = 0; i < count; i++) {
      if (lfoActive && (i & 15) === 0) {
        const raw = v.lfo.next(s.lfoShape, s.lfoRate, sr, 16);
        switch (s.lfoTarget) {
          case 'pitch':
            pitchRatio = semitonesToRatio(baseSemis + raw * lfoDepth * 2);
            rate = srRatio * pitchRatio * speed; transposeRate = srRatio * pitchRatio; break;
          case 'volume': tremolo = 1 - lfoDepth * (0.5 + 0.5 * raw); break;
          case 'cutoff':
            lfoOct = raw * lfoDepth * 3;
            if (filterActive && !filterEnvActive) v.filter.setParameters(baseCutoff * Math.pow(2, lfoOct), reso, sr);
            break;
          case 'pan': { const g = balanceGains(s.pan + raw * lfoDepth, this.panTmp); panL = g[0]; panR = g[1]; break; }
        }
      }
      if (filterEnvActive && (i & 15) === 0) {
        v.filter.setParameters(Math.min(baseCutoff * Math.pow(2, lfoOct + envAmount * v.env.level * 6), 20000), reso, sr);
      }
      let l = 0, r = 0, remaining;
      if (stretch) {
        const span = grainLen * transposeRate * dir;
        let w0;
        if (v.firstGrain && v.g0Phase < 0.5) w0 = 1;
        else { const sn = Math.sin(Math.PI * v.g0Phase); w0 = sn * sn; }
        let p0 = v.g0Start + v.g0Phase * span;
        if (looping) p0 = wrapPos(p0, rStart, rEnd, rLen);
        if (p0 >= rStart && p0 < rEnd) { readFrame(sample, p0, fr); l += fr[0] * w0; r += fr[1] * w0; }
        if (v.g1Phase >= 0) {
          const sn = Math.sin(Math.PI * v.g1Phase), w1 = sn * sn;
          let p1 = v.g1Start + v.g1Phase * span;
          if (looping) p1 = wrapPos(p1, rStart, rEnd, rLen);
          if (p1 >= rStart && p1 < rEnd) { readFrame(sample, p1, fr); l += fr[0] * w1; r += fr[1] * w1; }
        }
        v.g0Phase += grainInc;
        if (v.g0Phase >= 1) { v.g0Phase -= 1; v.g0Start = v.readHead; v.firstGrain = false; }
        const prev1 = v.g1Phase;
        v.g1Phase += grainInc;
        if (v.g1Phase >= 1) { v.g1Phase -= 1; v.g1Start = v.readHead; } else if (prev1 < 0 && v.g1Phase >= 0) v.g1Start = v.readHead;
        v.readHead += headRate * dir;
        if (dir > 0 && v.readHead >= rEnd) { if (looping) v.readHead = wrapPos(v.readHead, rStart, rEnd, rLen); else finished = true; }
        else if (dir < 0 && v.readHead < rStart) { if (looping) v.readHead = wrapPos(v.readHead, rStart, rEnd, rLen); else finished = true; }
        remaining = (dir > 0 ? rEnd - v.readHead : v.readHead - rStart) / headRate;
      } else {
        readFrame(sample, v.position, fr); l = fr[0]; r = fr[1];
        v.position += rate * dir;
        if (dir > 0 && v.position >= rEnd) { if (looping) v.position = wrapPos(v.position, rStart, rEnd, rLen); else finished = true; }
        else if (dir < 0 && v.position < rStart) { if (looping) v.position = wrapPos(v.position, rStart, rEnd, rLen); else finished = true; }
        remaining = (dir > 0 ? rEnd - v.position : v.position - rStart) / rate;
      }
      const env = v.env.next();
      let fade = 1;
      if (!looping && remaining < 48) fade = Math.max(0, remaining) / 48;
      if (v.fadeStep > 0) { v.fadeGain -= v.fadeStep; if (v.fadeGain <= 0) { v.fadeGain = 0; finished = true; } }
      if (filterActive) { v.filter.process(l, r); l = v.filter.outL; r = v.filter.outR; }
      if (drive > 0.0001) { l = distort(l, drive); r = distort(r, drive); }
      if (crushActive) { v.crusher.process(l, r, bits, ds); l = v.crusher.outL; r = v.crusher.outR; }
      const g = v.gain.next() * env * fade * v.fadeGain * tremolo;
      const oL = l * g * panL, oR = r * g * panR;
      const j = offset + i;
      dryL[j] += oL; dryR[j] += oR;
      if (!isPreview) {
        this.revL[j] += oL * revSend; this.revR[j] += oR * revSend;
        this.dlyL[j] += oL * dlySend; this.dlyR[j] += oR * dlySend;
      }
      const lv = env * v.fadeGain * v.velocityGain;
      if (lv > peak) peak = lv;
      if (finished || !v.env.isActive) { finished = true; break; }
    }
    v.level = peak;
    const li = isPreview ? PAD_COUNT : v.pad;
    if (peak > this.padLevels[li]) this.padLevels[li] = peak;
    if (finished) { v.active = false; v.sample = null; v.level = 0; }
  }

  _renderClick(offset, count) {
    const c = this.click;
    if (c.remaining <= 0) return;
    const inc = (2 * Math.PI * c.freq) / this.sampleRate;
    for (let i = 0; i < count && c.remaining > 0; i++) {
      const env = c.remaining / c.length;
      const s = Math.sin(c.phase) * env * env * 0.35;
      c.phase += inc;
      if (c.phase > 2 * Math.PI) c.phase -= 2 * Math.PI;
      this.postL[offset + i] += s; this.postR[offset + i] += s;
      c.remaining--;
    }
  }

  _processMaster(n, outL, outR, o) {
    const m = this.master, sr = this.sampleRate;
    this.delay.delaySeconds = effectiveDelaySeconds(m, this.seq.bpm);
    this.delay.process(this.dlyL, this.dlyR, this.wetDlyL, this.wetDlyR, n);
    this.reverb.process(this.revL, this.revR, this.wetRevL, this.wetRevR, n);
    this.delayMix.target = m.delayMix;
    this.reverbMix.target = m.reverbMix;
    this.masterVolume.target = m.volume * m.volume;
    const mode = m.filterMode;
    const bypass = mode === 'off' || (mode === 'lowPass' && m.filterCutoff >= 19500) || (mode === 'highPass' && m.filterCutoff <= 21);
    this.filterWet.target = bypass ? 0 : 1;
    if (mode !== 'off' && mode !== this.lastFilterMode) this.masterFilter.reset();
    if (mode !== 'off') { this.masterFilter.mode = mode; this.lastFilterMode = mode; }
    this.cutoffLog.target = Math.log2(clamp(m.filterCutoff, 20, 20000));
    if (!this.primed) {
      this.primed = true;
      for (const s of [this.masterVolume, this.delayMix, this.reverbMix, this.filterWet, this.cutoffLog]) s.reset(s.target);
    }
    const depth = m.modDepth, modActive = depth > 0.0001, target = m.modTarget;
    const drive = m.drive, bits = m.crushBits, ds = m.crushDownsample;
    const crushActive = bits < 15.99 || ds > 1.001;
    const eqActive = !this.eq.isFlat, compActive = this.comp.isActive;
    let modValue = 0, tremolo = 1, panL = 1, panR = 1;
    for (let i = 0; i < n; i++) {
      if ((i & 15) === 0) {
        const cl = this.cutoffLog.next();
        if (modActive) {
          modValue = this.modLFO.next(m.modShape, m.modRate, sr, 16);
          if (target === 'tremolo') tremolo = 1 - depth * (0.5 + 0.5 * modValue);
          else if (target === 'pan') { const g = balanceGains(modValue * depth, this.panTmp); panL = g[0]; panR = g[1]; }
        } else { tremolo = 1; panL = 1; panR = 1; }
        if (this.filterWet.current > 0 || this.filterWet.target > 0) {
          let oct = cl;
          if (modActive && target === 'filter') oct += modValue * depth * 3;
          this.masterFilter.setParameters(Math.pow(2, oct), m.filterResonance, sr);
        }
      }
      const dm = this.delayMix.next(), rm = this.reverbMix.next();
      let l = this.dryL[i] + this.wetDlyL[i] * dm + this.wetRevL[i] * rm;
      let r = this.dryR[i] + this.wetDlyR[i] * dm + this.wetRevR[i] * rm;
      const fw = this.filterWet.next();
      if (fw > 0) {
        this.masterFilter.process(l, r);
        l += (this.masterFilter.outL - l) * fw; r += (this.masterFilter.outR - r) * fw;
      }
      if (drive > 0.0001) { l = distort(l, drive); r = distort(r, drive); }
      if (crushActive) { this.masterCrusher.process(l, r, bits, ds); l = this.masterCrusher.outL; r = this.masterCrusher.outR; }
      if (modActive) {
        if (target === 'tremolo') { l *= tremolo; r *= tremolo; }
        else if (target === 'pan') { l *= panL; r *= panR; }
        else if (target === 'vibrato') { this.vibrato.process(l, r, modValue * depth); l = this.vibrato.outL; r = this.vibrato.outR; }
      }
      if (eqActive) { this.eq.process(l, r); l = this.eq.outL; r = this.eq.outR; }
      if (compActive) { this.comp.process(l, r); l = this.comp.outL; r = this.comp.outR; }
      const vol = this.masterVolume.next();
      let oL = l * vol + this.postL[i], oR = r * vol + this.postR[i];
      if (!Number.isFinite(oL) || !Number.isFinite(oR)) { this._resetEffects(); oL = 0; oR = 0; }
      outL[o + i] = oL > 1 ? 1 : oL < -1 ? -1 : oL;
      outR[o + i] = oR > 1 ? 1 : oR < -1 ? -1 : oR;
    }
  }

  _resetEffects() {
    this.delay.reset(); this.reverb.reset(); this.vibrato.reset(); this.masterFilter.reset(); this.eq.reset(); this.comp.reset();
    for (const v of this.voices) v.filter.reset();
  }

  _publishStatus(frames, outL, outR) {
    const st = this.status;
    let active = 0;
    for (const v of this.voices) if (v.active && !v.isFading) active++;
    st.activeVoices = active;
    st.transport = this.seq.state;
    st.currentStep = this.seq.displayStep;
    const loc = this.seq.locate(this.seq.position);
    st.currentPattern = loc.slot;
    st.songIndex = this.seq.song ? loc.songIndex : -1;
    st.queuedPattern = this.seq.queuedSlot;
    st.position = this.seq.position;
    st.gainReduction = this.comp.gr;
    let pl = 0, pr = 0;
    for (let i = 0; i < frames; i++) { const a = Math.abs(outL[i]), b = Math.abs(outR[i]); if (a > pl) pl = a; if (b > pr) pr = b; }
    st.peakL = Math.max(pl, st.peakL * 0.9);
    st.peakR = Math.max(pr, st.peakR * 0.9);
    for (let p = 0; p <= PAD_COUNT; p++) { st.padLevels[p] = this.padLevels[p]; this.padLevels[p] = 0; }
    st.padTriggers.set(this.padTriggers);
  }

  // ------------------------------------------------------------ Sequencer-Ereignisse & Aufnahme

  _recordHit(pad, velocity) {
    const pos = this.seq.position;
    this.lastManualHit[pad] = pos;
    const loc = this.seq.locate(pos);
    if (this.recordedHits.length < 256) {
      this.recordedHits.push({ pad, velocity, slot: loc.slot, positionInPattern: loc.step + loc.fraction, patternLength: loc.length });
    }
  }

  // ------------------------------------------------------------ Motion-Sequenz

  /** Wendet die Motion-Spuren des hörbaren Patterns an; true, wenn Spuren aktiv sind. */
  _applyMotion() {
    const loc = this.seq.locate(this.seq.position);
    const p = this.seq.patterns[loc.slot];
    if (this.motionMode === 'off' || !p || !p.motion || !p.motion.length) {
      if (this.motionTouchedPads || this.motionTouchedMaster) this._restoreMotion(true, 0, false);
      return false;
    }
    if ((this.motionTouchedPads & ~p.motionPadMask) || (this.motionTouchedMaster && !p.hasMasterMotion)) {
      this._restoreMotion(false, p.motionPadMask, p.hasMasterMotion);
    }
    const smooth = this.motionMode === 'smooth';
    let masterChanged = false;
    const mm = this.motionMaster;
    if (p.hasMasterMotion) Object.assign(mm, this.baseMaster);
    for (const tr of p.motion) {
      if (loc.step >= tr.hold.length) continue;
      let v;
      if (smooth) {
        const a = tr.smooth[loc.step], b = tr.smooth[(loc.step + 1) % tr.smooth.length];
        v = a + (b - a) * loc.fraction;
      } else v = tr.hold[loc.step];
      if (tr.pad >= 0) {
        this.padSettings[tr.pad][tr.key] = v;
        this.motionTouchedPads |= 1 << tr.pad;
      } else {
        mm[tr.key] = v;
        if (tr.last !== v || this.master !== mm) masterChanged = true;
        tr.last = v;
      }
    }
    if (p.hasMasterMotion) {
      if (masterChanged) this.applyMaster(mm);
      this.motionTouchedMaster = true;
    }
    return true;
  }

  _restoreMotion(all, keepPads, keepMaster) {
    const restore = all ? this.motionTouchedPads : this.motionTouchedPads & ~keepPads;
    if (restore) {
      for (let p = 0; p < PAD_COUNT; p++) if (restore & (1 << p)) Object.assign(this.padSettings[p], this.basePadSettings[p]);
      this.motionTouchedPads &= ~restore;
    }
    if (this.motionTouchedMaster && (all || !keepMaster)) {
      this.applyMaster(this.baseMaster);
      this.motionTouchedMaster = false;
    }
  }

  _handleSeqEvent(e) {
    if (e.kind === 0) {
      if (this.isRecording && Math.abs(e.time - this.lastManualHit[e.pad]) < 0.5) return;
      this._startVoice(e.pad, e.velocity, true, 0);
    } else if (e.kind === 1) {
      this._releasePad(e.pad, true);
    } else {
      const c = this.click;
      c.freq = e.pad === 1 ? 1600 : 1000; c.length = Math.floor(0.03 * this.sampleRate); c.remaining = c.length; c.phase = 0;
    }
  }

  // ------------------------------------------------------------ Stimmenverwaltung

  _resetVoice(v) {
    v.active = false; v.isPreview = false; v.sample = null; v.position = 0; v.readHead = 0;
    v.g0Start = 0; v.g0Phase = 0; v.g1Start = 0; v.g1Phase = -0.5; v.firstGrain = true;
    v.env.reset(); v.filter.reset(); v.crusher.reset(); v.lfo.reset();
    v.velocityGain = 1; v.fadeGain = 1; v.fadeStep = 0; v.fromSequencer = false; v.released = false; v.level = 0; v.transpose = 0;
  }

  _startVoice(pad, velocity, fromSequencer, transpose) {
    if (pad < 0 || pad >= PAD_COUNT) return;
    const sample = this.padSamples[pad];
    if (!sample) return;
    const s = this.padSettings[pad];
    if (s.chokeGroup > 0 || s.mono) {
      for (const v of this.voices) {
        if (!v.active || v.isFading) continue;
        if ((s.mono && v.pad === pad) || (s.chokeGroup > 0 && v.pad !== pad && this.padSettings[v.pad].chokeGroup === s.chokeGroup)) {
          this._beginFade(v, 0.004);
        }
      }
    }
    let activeCount = 0;
    for (const v of this.voices) if (v.active && !v.isFading) activeCount++;
    if (activeCount >= this.engineSettings.polyphony) {
      if (this.engineSettings.stealMode === 'none') return;
      const victim = this._chooseVictim(pad);
      if (victim) this._beginFade(victim, 0.003);
    }
    let slot = this.voices.find((v) => !v.active);
    if (!slot) {
      let bestScore = Infinity;
      for (const v of this.voices) {
        const score = v.isFading ? v.fadeGain - 10 : v.age % 1000000;
        if (score < bestScore) { bestScore = score; slot = v; }
      }
    }
    const v = slot;
    this._resetVoice(v);
    this.voiceCounter++;
    v.active = true; v.pad = pad; v.sample = sample; v.age = this.voiceCounter; v.fromSequencer = fromSequencer;
    v.transpose = clamp(transpose, -48, 48);
    const frames = sample.frameCount;
    const rStart = clamp(s.start, 0, 1) * frames;
    const rEnd = Math.max(clamp(s.end, 0, 1) * frames, rStart + 2);
    const startPos = s.reverse ? Math.min(rEnd, frames) - 1 : rStart;
    v.position = startPos; v.readHead = startPos; v.g0Start = startPos; v.g1Start = startPos;
    const vel = clamp(velocity, 0, 1), sens = clamp(s.velocitySensitivity, 0, 1);
    v.velocityGain = 1 - sens + sens * vel * vel;
    v.gain.reset(s.volume * v.velocityGain);
    v.gain.coeff = Math.exp(-1 / (0.005 * this.sampleRate));
    v.env.configure(s.attack, s.decay, s.sustain, s.release, this.sampleRate);
    v.env.noteOn();
    this.padTriggers[pad]++;
  }

  _chooseVictim(pad) {
    const mode = this.engineSettings.stealMode;
    let best = null;
    if (mode === 'quietest') {
      let bestLevel = Infinity;
      for (const v of this.voices) {
        if (!v.active || v.isFading) continue;
        const level = v.level === 0 ? 1 : v.level;
        if (level < bestLevel) { bestLevel = level; best = v; }
      }
      return best;
    }
    let bestAge = Infinity;
    if (mode === 'samePad') {
      for (const v of this.voices) if (v.active && !v.isFading && v.pad === pad && v.age < bestAge) { bestAge = v.age; best = v; }
      if (best) return best;
    }
    for (const v of this.voices) if (v.active && !v.isFading && v.age < bestAge) { bestAge = v.age; best = v; }
    return best;
  }

  _enforcePolyphony() {
    let active = this.voices.filter((v) => v.active && !v.isFading).length;
    while (active > this.engineSettings.polyphony) {
      let oldest = null;
      for (const v of this.voices) if (v.active && !v.isFading && (!oldest || v.age < oldest.age)) oldest = v;
      if (!oldest) break;
      this._beginFade(oldest, 0.003);
      active--;
    }
  }

  _beginFade(v, seconds) {
    if (!v.active || v.isFading) return;
    v.fadeStep = 1 / (Math.max(seconds, 0.0005) * this.sampleRate);
  }

  _releasePad(pad, fromSequencer) {
    if (pad < 0 || pad >= PAD_COUNT) return;
    if (this.padSettings[pad].playMode === 'oneShot') return;
    for (const v of this.voices) {
      if (v.active && v.pad === pad && v.fromSequencer === fromSequencer && !v.released) { v.env.noteOff(); v.released = true; }
    }
  }

  _releaseSequencerVoices() {
    this.seq.discardPendingNotes();
    for (const v of this.voices) {
      if (v.active && v.fromSequencer && !v.released && this.padSettings[v.pad].playMode !== 'oneShot') { v.env.noteOff(); v.released = true; }
    }
  }

  get sequencerPosition() { return this.seq.position; }
  get sequencerSlot() { return this.seq.locate(this.seq.position).slot; }
}

/** Hilfsfunktion: Sample-Objekt aus Kanaldaten. */
export function makeSample(channels, sampleRate, name = '') {
  const left = channels[0] instanceof Float32Array ? channels[0] : Float32Array.from(channels[0]);
  const right = channels.length > 1 ? (channels[1] instanceof Float32Array ? channels[1] : Float32Array.from(channels[1])) : left;
  return { name, left, right, sampleRate, frameCount: Math.max(1, left.length), stereo: channels.length > 1 };
}
