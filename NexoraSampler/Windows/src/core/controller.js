// Zentrale Steuerung (Gegenstück zu SamplerController.swift): Projektzustand, Engine-Synchronisation,
// Pads, Sequencer, Dateien, Bibliothek, MIDI und Export.
import { bridge, join, basename, stem, extname, isAudioPath } from './bridge.js';
import { AudioHost, overview } from './audio.js';
import { Library, FACTORY_PREFIX } from './library.js';
import { writeProject, readProject, resolveSample, PresetStore, packageDirFor } from './projectio.js';
import { MIDIInput, noteName } from './midi.js';
import { patternSnapshot, makeSample } from '../engine/engine.js';
import {
  PARAMS, newProject, newPattern, normalizePattern, getValue, setValue, toNormalized, fromNormalized, formatValue,
  muteMask, slotName, placeHit, quantizePattern, QUANTIZE_NAMES, defaultPadSettings, defaultMaster, DEFAULT_KEYS,
  PATTERN_SLOTS, MAX_STEPS, STEPS_PER_PAGE, PAGE_COUNT, SONG_MAX_LENGTH, MOTION_MODES, canRecordMotion, recordMotion,
  hasMotion, motionLaneName
} from '../engine/model.js';
import { slices as computeSlices, patternSteps as slicePatternSteps } from '../engine/slicer.js';
import { SampleRecorder } from '../engine/recorder.js';

const PREFS_KEY = 'nexora.prefs';
const DEFAULT_PREFS = {
  theme: 'crimson', velocityFromPosition: true, keyboardVelocity: 0.85, selectOnHit: true, copyImports: true,
  autoPreview: true, previewVolume: 0.8, midiEnabled: true, latencyHint: 'interactive', sinkId: ''
};

export const DRAWERS = [
  ['editor', 'PAD EDIT'], ['sequencer', 'SEQUENCER'], ['song', 'SONG & MOTION'], ['sampling', 'SAMPLING'],
  ['browser', 'SAMPLE BROWSER'], ['effects', 'MASTER FX'], ['kits', 'KITS & PRESETS'], ['midi', 'MIDI']
];

export const LFO_TARGET_NAMES = { off: 'OFF', pitch: 'VIB', volume: 'TREM', cutoff: 'FILT', pan: 'PAN' };
export const LFO_SHAPE_NAMES = { sine: 'SIN', triangle: 'TRI', square: 'SQR', sawUp: 'SAW', sawDown: 'RMP', sampleHold: 'S&H' };
export const PLAY_MODE_NAMES = { oneShot: 'ONE', gate: 'GATE', loop: 'LOOP' };
export const FILTER_NAMES = { off: 'OFF', lowPass: 'LP', highPass: 'HP', bandPass: 'BP' };
export const MOD_TARGET_NAMES = { filter: 'FILTER', tremolo: 'TREMOLO', vibrato: 'VIBRATO', pan: 'AUTOPAN' };
export const cycle = (list, v) => list[(list.indexOf(v) + 1) % list.length];

/** Keyboard-Modus: untere Reihe (Pads 9–16) weiße Tasten C … C', obere Reihe schwarze Tasten. */
export function keyboardSemitone(pad) {
  const white = [0, 2, 4, 5, 7, 9, 11, 12];
  const black = [null, 1, 3, null, 6, 8, 10, null];
  if (pad >= 8 && pad < 16) return white[pad - 8];
  if (pad >= 0 && pad < 8) return black[pad];
  return null;
}

export class Controller {
  constructor() {
    this.listeners = new Set();
    this.prefs = { ...DEFAULT_PREFS, ...this._loadPrefs() };
    this.audio = new AudioHost();
    this.audio.onStatus = (s) => this._onStatus(s);
    this.project = newProject('Untitled');
    this.padSamples = new Array(16).fill(null);
    this.padWaveforms = new Array(16).fill(null);
    this.padSources = new Array(16).fill(null);
    this.selectedPad = 0;
    this.padMode = 'play';
    this.drawer = null;
    this.isRecording = false;
    this.lcd = null;
    this.midiLearnActive = false;
    this.learnTarget = null;
    this.noteLearnPad = null;
    this.xyLatch = true;
    this.projectPath = null;
    this.dirty = false;
    this.patternBank = 0;
    this.keyboardOctave = 0;
    this.keyboardHeld = new Set();
    this.loadingPads = new Set();
    this.exportProgress = null;
    this.exportCancelled = false;
    this.notice = null;
    this.midiNames = [];
    this.tapTimes = [];
    this.clipboard = null;
    this.presetRevision = 0;
    this.libraryRevision = 0;
    this.selectedCollection = null;
    this.selectedItem = null;
    this.searchText = '';
    this.meters = {
      padGlow: new Float32Array(16), currentStep: 0, transport: 'stopped', currentPattern: 0, queuedPattern: -1,
      peakL: 0, peakR: 0, activeVoices: 0, gainReduction: 0, midiActivityUntil: 0, songIndex: -1
    };
    /** Sichtbare Seite (0 … 3) im Raster und Step-Modus; `followPage` = folgt der Wiedergabe */
    this.stepPage = 0;
    this.followPage = true;
    this._motionLast = null;
    this._motionPushTimer = null;
    this.sampling = {
      source: 'input', deviceId: '', thresholdDb: null, maxSeconds: 60, monitor: false, startPlayback: true,
      targetPad: 0, active: false, state: 'idle', level: 0, seconds: 0, devices: []
    };
    this._capture = null;
    this.resampling = false;
    this._lastTriggers = new Array(16).fill(0);
    this._flash = new Float32Array(16);
  }

  // ------------------------------------------------------------ Grundlagen

  on(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  changed() { for (const fn of this.listeners) fn(); }

  _loadPrefs() { try { return JSON.parse(localStorage.getItem(PREFS_KEY) ?? '{}'); } catch { return {}; } }
  setPref(key, value) {
    this.prefs[key] = value;
    try { localStorage.setItem(PREFS_KEY, JSON.stringify(this.prefs)); } catch { /* optional */ }
    if (key === 'midiEnabled') this.changed();
    this.changed();
  }

  report(title, message) {
    if (this.info?.screenshots) { console.log(`[NEXORA] ${title}: ${message}`); return; }
    this.notice = { title, message };
    this.changed();
  }

  async init() {
    this.info = await bridge.info();
    this.library = new Library(this.info);
    this.presets = new PresetStore(this.info);
    await this.library.load();
    this.selectedCollection = this.library.collections[0]?.id ?? null;
    try {
      await this.audio.start({ latencyHint: this.prefs.latencyHint, sinkId: this.prefs.sinkId });
    } catch (err) {
      this.report('Audio', `Die Audioausgabe konnte nicht gestartet werden: ${err.message ?? err}`);
    }
    this.midi = new MIDIInput((m) => this._onMIDI(m), (names) => { this.midiNames = names; this.changed(); });
    await this.midi.start();
    await this.loadClassicKit(true);
    this.dirty = false;
    this._updateTitle();
    if (this.info.openProject) await this.openProject(this.info.openProject, false);
    bridge.onMenu((id) => this.menu(id));
    bridge.onCloseRequest(async () => { if (await this.confirmDiscard()) bridge.closeConfirmed(); });
    this.changed();
  }

  markDirty() { if (!this.dirty) { this.dirty = true; this._updateTitle(); } }
  _updateTitle() { bridge.setTitle(`${this.project.name}${this.dirty ? ' •' : ''} – NEXORA Sampler`); }

  send(cmd) { this.audio.send(cmd); }

  pushFullState() {
    for (let i = 0; i < 16; i++) {
      this.send({ cmd: 'setPadSettings', pad: i, settings: this.project.pads[i].settings });
      this.send({ cmd: 'setSample', pad: i, sample: this.padSamples[i] });
    }
    this.send({ cmd: 'setMaster', master: this.project.master });
    this.send({ cmd: 'setEngineSettings', settings: this.project.engine });
    this.send({ cmd: 'setTempo', bpm: this.project.bpm, swing: this.project.swing });
    this.sendTrackStates();
    for (let s = 0; s < PATTERN_SLOTS; s++) this.pushPattern(s);
    this.send({ cmd: 'selectPattern', slot: this.project.sequencer.currentPattern, immediately: true });
    this.send({ cmd: 'setMetronome', on: this.project.sequencer.metronome });
    this.send({ cmd: 'setRecording', on: this.isRecording });
    this.send({ cmd: 'setMotionMode', mode: this.project.sequencer.motionMode });
    this.sendSong();
  }

  pushPattern(slot) { this.send({ cmd: 'setPattern', slot, pattern: patternSnapshot(this.project.sequencer.patterns[slot]) }); }
  sendTrackStates() { this.send({ cmd: 'setTrackStates', mutes: muteMask(this.project.sequencer.trackMutes), solos: muteMask(this.project.sequencer.trackSolos) }); }

  _apply(scope) {
    if (scope === 'master') this.send({ cmd: 'setMaster', master: this.project.master });
    else if (scope === 'tempo') this.send({ cmd: 'setTempo', bpm: this.project.bpm, swing: this.project.swing });
    else this.send({ cmd: 'setPadSettings', pad: scope.pad, settings: this.project.pads[scope.pad].settings });
  }

  // ------------------------------------------------------------ Parameter

  normalized(id, pad = this.selectedPad) { return toNormalized(id, getValue(this.project, id, pad)); }
  display(id, pad = this.selectedPad) { return formatValue(id, getValue(this.project, id, pad)); }

  setParameter(id, n, pad = null, showOnLCD = true) {
    const target = pad ?? this.selectedPad;
    this._apply(setValue(this.project, id, fromNormalized(id, n), target));
    this._recordMotionValue(id, target);
    if (showOnLCD) this.showParameter(id, target);
    this.markDirty();
    this.changed();
  }

  setParameterValue(id, value, pad = null) {
    const target = pad ?? this.selectedPad;
    this._apply(setValue(this.project, id, value, target));
    this._recordMotionValue(id, target);
    this.showParameter(id, target);
    this.markDirty();
    this.changed();
  }

  showParameter(id, pad = this.selectedPad) {
    const prefix = PARAMS[id].pad ? `P${String(pad + 1).padStart(2, '0')} ` : '';
    this.showLCD(prefix + PARAMS[id].name.toUpperCase(), formatValue(id, getValue(this.project, id, pad)));
  }

  showLCD(title, value, seconds = 1.6) {
    this.lcd = { title, value, expires: performance.now() + seconds * 1000 };
    this.changed();
  }

  updatePad(i, fn) {
    fn(this.project.pads[i]);
    this.send({ cmd: 'setPadSettings', pad: i, settings: this.project.pads[i].settings });
    this.markDirty();
    this.changed();
  }

  updateMaster(fn) {
    fn(this.project.master);
    this.send({ cmd: 'setMaster', master: this.project.master });
    this.markDirty();
    this.changed();
  }

  updateEngine(fn) {
    fn(this.project.engine);
    this.send({ cmd: 'setEngineSettings', settings: this.project.engine });
    this.showLCD('POLYPHONY', `${this.project.engine.polyphony} · ${this.project.engine.stealMode.toUpperCase()}`);
    this.markDirty();
  }

  setXY(x, y) {
    const { xParameter: xp, yParameter: yp } = this.project.xyPad;
    this.setParameter(xp, x, null, false);
    this.setParameter(yp, y, null, false);
    this.showLCD(`X ${PARAMS[xp].short} · Y ${PARAMS[yp].short}`, `${this.display(xp)} / ${this.display(yp)}`, 1);
  }

  assignXY(axis, id) {
    this.project.xyPad[axis === 'x' ? 'xParameter' : 'yParameter'] = id;
    this.showLCD(`XY ${axis.toUpperCase()}-AXIS`, PARAMS[id].name.toUpperCase());
    this.markDirty();
  }

  // ------------------------------------------------------------ Status der Engine

  _onStatus(s) {
    if (s.type !== 'status') return;
    const m = this.meters;
    for (let p = 0; p < 16; p++) {
      if (s.padTriggers[p] !== this._lastTriggers[p]) { this._lastTriggers[p] = s.padTriggers[p]; this._flash[p] = 1; }
      else this._flash[p] = Math.max(0, this._flash[p] - 0.12);
      m.padGlow[p] = Math.max(this._flash[p], Math.min(1, s.padLevels[p]) * 0.9);
    }
    m.currentStep = s.currentStep; m.transport = s.transport; m.currentPattern = s.currentPattern;
    m.queuedPattern = s.queuedPattern; m.peakL = s.peakL; m.peakR = s.peakR; m.activeVoices = s.activeVoices;
    m.gainReduction = s.gainReduction;
    m.songIndex = s.songIndex ?? -1;
    if (this.followPage && m.transport === 'playing') {
      const page = Math.floor(m.currentStep / STEPS_PER_PAGE);
      if (page !== this.stepPage) this.stepPage = page;
    }
    if (m.transport === 'playing' && m.currentPattern !== this.project.sequencer.currentPattern) {
      this.project.sequencer.currentPattern = m.currentPattern;
      this.patternBank = Math.floor(m.currentPattern / 4);
    }
    if (s.hits) for (const h of s.hits) this._recordedHit(h);
    if (this.lcd && this.lcd.expires < performance.now()) this.lcd = null;
    this.changed();
  }

  _recordedHit(h) {
    const pattern = this.project.sequencer.patterns[h.slot];
    if (!pattern) return;
    const place = placeHit(h.positionInPattern, h.patternLength, this.project.sequencer.quantize, this.project.swing);
    pattern.steps[h.pad][place.step] = { active: true, velocity: h.velocity, offset: place.offset };
    this.pushPattern(h.slot);
    this.markDirty();
  }

  // ------------------------------------------------------------ Pads

  padDown(pad, velocity) {
    if (pad < 0 || pad > 15) return;
    if (this.padMode === 'play') {
      this.send({ cmd: 'noteOn', pad, velocity });
      if (this.prefs.selectOnHit && this.selectedPad !== pad) { this.selectedPad = pad; this.changed(); }
    } else if (this.padMode === 'step') {
      this.toggleStep(this.selectedPad, this.stepPage * STEPS_PER_PAGE + pad);
    } else {
      const semi = keyboardSemitone(pad);
      if (semi == null) return;
      this.keyboardHeld.add(pad);
      this.send({ cmd: 'noteOnTransposed', pad: this.selectedPad, velocity, semitones: semi + this.keyboardOctave * 12 });
      this.changed();
    }
  }

  padUp(pad) {
    if (this.padMode === 'play') this.send({ cmd: 'noteOff', pad });
    else if (this.padMode === 'keyboard') {
      this.keyboardHeld.delete(pad);
      if (!this.keyboardHeld.size) this.send({ cmd: 'noteOff', pad: this.selectedPad });
      this.changed();
    }
  }

  selectPad(pad) {
    this.selectedPad = (pad + 16) % 16;
    const s = this.padSamples[this.selectedPad];
    this.showLCD(`PAD ${String(this.selectedPad + 1).padStart(2, '0')}`, `${this.project.pads[this.selectedPad].name} · ${s ? (s.frameCount / s.sampleRate).toFixed(2) + 's' : 'EMPTY'}`);
  }

  setPadMode(mode) {
    if (this.padMode === 'keyboard' && mode !== 'keyboard') { this.keyboardHeld.clear(); this.send({ cmd: 'noteOff', pad: this.selectedPad }); }
    this.padMode = mode;
    const name = this.project.pads[this.selectedPad].name;
    this.showLCD(mode === 'keyboard' ? 'KEYBOARD' : 'MODE', mode === 'play' ? 'TRIGGER' : mode === 'step' ? `SEQUENCER · PAD ${String(this.selectedPad + 1).padStart(2, '0')}` : `${name} · OCT ${this.keyboardOctave}`, 1.2);
  }

  toggleDrawer(d) { this.drawer = this.drawer === d ? null : d; this.changed(); }

  exitAction() {
    if (this.drawer) this.drawer = null;
    else if (this.midiLearnActive) this.toggleMIDILearn();
    else if (this.padMode !== 'play') this.setPadMode('play');
    this.changed();
  }

  _setPadSample(pad, sample, source) {
    this.padSamples[pad] = sample;
    this.padWaveforms[pad] = sample ? overview(sample) : null;
    this.padSources[pad] = source;
    this.send({ cmd: 'setSample', pad, sample });
  }

  async _assignLoaded(pad, sample, source, ref, name) {
    const p = this.project.pads[pad];
    p.sample = ref;
    p.name = String(name).toUpperCase().slice(0, 14);
    p.settings.start = 0; p.settings.end = 1;
    this._setPadSample(pad, sample, source);
    this.send({ cmd: 'setPadSettings', pad, settings: p.settings });
    this.selectedPad = pad;
    this.showLCD(`PAD ${String(pad + 1).padStart(2, '0')} LOADED`, `${p.name} ${(sample.sampleRate / 1000).toFixed(1)}k ${sample.stereo ? 'ST' : 'MONO'}`);
    this.markDirty();
  }

  async loadSampleFromPath(path, pad = this.selectedPad, libraryItemID = null) {
    this.loadingPads.add(pad); this.changed();
    try {
      const bytes = await bridge.read(path);
      const sample = await this.audio.decode(bytes, stem(path));
      const size = await bridge.size(path);
      await this._assignLoaded(pad, sample, { type: 'file', path }, {
        fileName: basename(path), originalPath: path, libraryItemID: libraryItemID ?? undefined, fileSize: size ?? undefined,
        frameCount: sample.frameCount, sampleRate: sample.sampleRate
      }, stem(path));
    } catch (err) {
      this.report('Sample konnte nicht geladen werden', `${basename(path)}: ${err.message ?? err}`);
    } finally { this.loadingPads.delete(pad); this.changed(); }
  }

  async loadLibraryItem(item, pad = this.selectedPad) {
    const loc = this.library.location(item);
    if (loc?.path) return this.loadSampleFromPath(loc.path, pad, item.id);
    this.loadingPads.add(pad); this.changed();
    try {
      const bytes = await this.library.bytes(item);
      const sample = await this.audio.decode(bytes, item.name);
      await this._assignLoaded(pad, sample, { type: 'bytes', bytes, ext: 'wav', name: item.name }, {
        fileName: `${item.name}.wav`, libraryItemID: item.factoryID ?? item.id, frameCount: sample.frameCount, sampleRate: sample.sampleRate
      }, item.name);
    } catch (err) {
      this.report('Sample konnte nicht geladen werden', `${item.name}: ${err.message ?? err}`);
    } finally { this.loadingPads.delete(pad); this.changed(); }
  }

  /** Dateien aus dem Explorer/Browser auf ein Pad. Mehrere werden auf Folge-Pads verteilt. */
  async handleDrop(dataTransfer, pad) {
    const itemId = dataTransfer.getData('application/x-nexora-item');
    if (itemId) {
      const item = this.library.item(itemId);
      if (item) await this.loadLibraryItem(item, pad);
      return;
    }
    const files = [...(dataTransfer.files ?? [])];
    let offset = 0;
    for (const f of files.slice(0, 16)) {
      const target = (pad + offset) % 16;
      const path = bridge.pathForFile?.(f);
      if (path && isAudioPath(path)) { await this.loadSampleFromPath(path, target); offset++; }
      else if (!path && isAudioPath(f.name)) {
        const bytes = new Uint8Array(await f.arrayBuffer());
        try {
          const sample = await this.audio.decode(bytes, stem(f.name));
          await this._assignLoaded(target, sample, { type: 'bytes', bytes, ext: extname(f.name), name: stem(f.name) },
            { fileName: f.name, frameCount: sample.frameCount, sampleRate: sample.sampleRate }, stem(f.name));
          offset++;
        } catch (err) { this.report('Sample konnte nicht geladen werden', `${f.name}: ${err.message ?? err}`); }
      }
    }
    if (!offset && files.length) this.report('Nicht unterstütztes Format', 'Unterstützt werden WAV, AIFF, MP3, M4A, FLAC und OGG.');
  }

  async chooseSampleForSelectedPad() {
    const [path] = await bridge.openFiles({ kind: 'audio', title: `Sample für Pad ${this.selectedPad + 1}` });
    if (path) await this.loadSampleFromPath(path, this.selectedPad);
  }

  clearPad(pad) {
    this._setPadSample(pad, null, null);
    const p = this.project.pads[pad];
    delete p.sample;
    p.name = `PAD ${pad + 1}`;
    this.send({ cmd: 'setPadSettings', pad, settings: p.settings });
    this.markDirty(); this.changed();
  }

  renamePad(pad, name) {
    const n = String(name).trim();
    if (!n) return;
    this.project.pads[pad].name = n.slice(0, 20);
    this.markDirty(); this.changed();
  }

  setPadKey(pad, key) {
    const k = String(key).toLowerCase().slice(0, 1);
    for (const p of this.project.pads) if (p.index !== pad && k && p.keyboardKey === k) p.keyboardKey = '';
    this.project.pads[pad].keyboardKey = k;
    this.markDirty(); this.changed();
  }

  // ------------------------------------------------------------ Werks-Kits

  async _factoryBytes(file) {
    const res = await fetch(this.library.factoryURL + encodeURI(file).replace(/#/g, '%23'));
    if (!res.ok) throw new Error(file);
    return new Uint8Array(await res.arrayBuffer());
  }

  async loadClassicKit(resetPatterns) {
    const f = this.library.factory;
    if (!f) { this.report('Werks-Klänge fehlen', 'Die Werks-Bibliothek wurde nicht gefunden (resources/factory).'); return; }
    this.loadingPads = new Set([...Array(16).keys()]); this.changed();
    for (let i = 0; i < 16 && i < f.classicKit.length; i++) {
      const pad = f.classicKit[i];
      try {
        const bytes = await this._factoryBytes(pad.file);
        const sample = await this.audio.decode(bytes, pad.name);
        const p = this.project.pads[i];
        p.name = pad.name;
        p.settings = { ...defaultPadSettings(), ...pad.settings };
        p.sample = { fileName: `${pad.name}.wav`, frameCount: sample.frameCount, sampleRate: sample.sampleRate };
        this._setPadSample(i, sample, { type: 'bytes', bytes, ext: 'wav', name: pad.name });
      } catch (err) { console.warn(err); }
    }
    this.project.kitName = f.classicKitName;
    if (resetPatterns) {
      const seq = newProject().sequencer;
      f.demoPatterns.forEach((p, i) => { seq.patterns[i] = normalizePattern(p); });
      this.project.sequencer = seq;
    }
    this.loadingPads.clear();
    this.pushFullState();
    this.showLCD('KIT', f.classicKitName.toUpperCase());
    this.markDirty();
  }

  async loadFactoryKit(kit) {
    this.loadingPads = new Set([...Array(16).keys()]);
    this.showLCD('LOADING KIT', kit.name.toUpperCase());
    for (let i = 0; i < 16; i++) {
      const sound = this.library.factorySound(kit.soundIDs[i]);
      if (!sound) continue;
      try {
        const bytes = await this._factoryBytes(sound.file);
        const sample = await this.audio.decode(bytes, sound.name);
        const p = this.project.pads[i];
        p.name = sound.name.toUpperCase();
        p.settings = { ...defaultPadSettings(), ...sound.settings };
        p.sample = { fileName: `${sound.name}.wav`, libraryItemID: sound.id, frameCount: sample.frameCount, sampleRate: sample.sampleRate };
        this._setPadSample(i, sample, { type: 'bytes', bytes, ext: 'wav', name: sound.name });
        this.send({ cmd: 'setPadSettings', pad: i, settings: p.settings });
      } catch (err) { console.warn(err); }
    }
    this.project.kitName = kit.name;
    this.loadingPads.clear();
    this.showLCD('KIT', kit.name.toUpperCase());
    this.markDirty();
  }

  clearAllPads() {
    for (let i = 0; i < 16; i++) {
      this._setPadSample(i, null, null);
      this.project.pads[i] = { index: i, name: `PAD ${i + 1}`, settings: defaultPadSettings(), keyboardKey: this.project.pads[i].keyboardKey };
      this.send({ cmd: 'setPadSettings', pad: i, settings: this.project.pads[i].settings });
    }
    this.project.kitName = 'Empty Kit';
    this.showLCD('KIT', 'CLEARED');
    this.markDirty();
  }

  // ------------------------------------------------------------ Vorhören

  async preview(item) {
    try {
      const sample = await this.audio.decode(await this.library.bytes(item), item.name);
      this.send({ cmd: 'preview', sample, gain: this.prefs.previewVolume });
      this.showLCD('PREVIEW', `${item.name.toUpperCase()} ${(sample.frameCount / sample.sampleRate).toFixed(2)}s`);
    } catch (err) { this.report('Vorhören nicht möglich', err.message ?? String(err)); }
  }

  stopPreview() { this.send({ cmd: 'preview', sample: null, gain: 1 }); }

  // ------------------------------------------------------------ Transport & Sequencer

  play() { this.send({ cmd: 'transport', transport: 'play' }); this.showLCD('PLAY', `PATTERN ${slotName(this.project.sequencer.currentPattern)}`, 0.8); }
  pause() { this.send({ cmd: 'transport', transport: 'pause' }); this.showLCD('PAUSE', '', 0.8); }
  stop() { this.send({ cmd: 'transport', transport: 'stop' }); this.showLCD('STOP', '', 0.8); }
  togglePlay() { if (this.meters.transport === 'playing') this.stop(); else this.play(); }
  playPause() { if (this.meters.transport === 'playing') this.pause(); else this.play(); }

  toggleRecord() {
    this.isRecording = !this.isRecording;
    this._motionLast = null;
    this.send({ cmd: 'setRecording', on: this.isRecording });
    this.showLCD('RECORD', this.isRecording ? `ARMED · Q ${QUANTIZE_NAMES[this.project.sequencer.quantize]}` : 'OFF');
    if (this.isRecording && this.meters.transport !== 'playing') this.play();
  }

  toggleMetronome() {
    const seq = this.project.sequencer;
    seq.metronome = !seq.metronome;
    this.send({ cmd: 'setMetronome', on: seq.metronome });
    this.showLCD('METRONOME', seq.metronome ? 'ON' : 'OFF');
    this.markDirty();
  }

  tapTempo() {
    const now = performance.now();
    this.tapTimes = this.tapTimes.filter((t) => now - t < 2500);
    this.tapTimes.push(now);
    if (this.tapTimes.length < 2) { this.showLCD('TAP', '…', 1); return; }
    const intervals = this.tapTimes.slice(1).map((t, i) => t - this.tapTimes[i]);
    const avg = intervals.reduce((a, b) => a + b, 0) / intervals.length / 1000;
    if (avg > 0) this.setParameterValue('tempo', Math.round((60 / avg) * 10) / 10);
  }

  selectPattern(slot) {
    if (slot < 0 || slot >= PATTERN_SLOTS) return;
    this.patternBank = Math.floor(slot / 4);
    const immediate = this.meters.transport !== 'playing' || !this.project.sequencer.switchAtBarEnd;
    this.send({ cmd: 'selectPattern', slot, immediately: immediate });
    if (immediate) { this.project.sequencer.currentPattern = slot; this.showLCD('PATTERN', slotName(slot)); }
    else this.showLCD('NEXT PATTERN', `${slotName(slot)} AT BAR END`);
    this.markDirty();
  }

  stepPattern(delta) { this.selectPattern(((this.project.sequencer.currentPattern + delta) % PATTERN_SLOTS + PATTERN_SLOTS) % PATTERN_SLOTS); }

  get currentPattern() { return this.project.sequencer.patterns[this.project.sequencer.currentPattern]; }

  toggleStep(track, step) {
    const slot = this.project.sequencer.currentPattern;
    const p = this.project.sequencer.patterns[slot];
    if (step >= p.length) return;
    const st = p.steps[track][step];
    p.steps[track][step] = st.active ? { ...st, active: false } : { active: true, velocity: this.prefs.keyboardVelocity, offset: 0 };
    this.pushPattern(slot);
    this.showLCD(`STEP ${String(step + 1).padStart(2, '0')} · ${this.project.pads[track].name}`, p.steps[track][step].active ? 'ON' : 'OFF', 0.9);
    this.markDirty();
  }

  cycleStepVelocity(track, step) {
    const slot = this.project.sequencer.currentPattern;
    const st = this.project.sequencer.patterns[slot].steps[track][step];
    if (!st.active) return this.toggleStep(track, step);
    st.velocity = st.velocity > 0.85 ? 0.7 : st.velocity > 0.55 ? 0.4 : 1;
    this.pushPattern(slot);
    this.showLCD(`STEP ${String(step + 1).padStart(2, '0')} VELOCITY`, `${Math.round(st.velocity * 100)}%`, 0.9);
    this.markDirty();
  }

  setPatternLength(n) {
    const slot = this.project.sequencer.currentPattern;
    this.project.sequencer.patterns[slot].length = Math.min(Math.max(n, 1), MAX_STEPS);
    this.stepPage = Math.min(this.stepPage, Math.ceil(this.project.sequencer.patterns[slot].length / STEPS_PER_PAGE) - 1);
    this.pushPattern(slot);
    this.showLCD('PATTERN LENGTH', `${this.project.sequencer.patterns[slot].length} STEPS`);
    this.markDirty();
  }

  setTrackGate(track, steps) {
    const slot = this.project.sequencer.currentPattern;
    this.project.sequencer.patterns[slot].gates[track] = Math.min(Math.max(steps, 0.25), 16);
    this.pushPattern(slot); this.markDirty(); this.changed();
  }

  clearCurrentPattern() {
    const slot = this.project.sequencer.currentPattern;
    const p = this.project.sequencer.patterns[slot];
    for (const t of p.steps) for (let s = 0; s < MAX_STEPS; s++) t[s] = { active: false, velocity: 0.8, offset: 0 };
    this.pushPattern(slot);
    this.showLCD(`PATTERN ${slotName(slot)}`, 'CLEARED');
    this.markDirty();
  }

  clearTrack(track) {
    const slot = this.project.sequencer.currentPattern;
    this.project.sequencer.patterns[slot].steps[track] = Array.from({ length: MAX_STEPS }, () => ({ active: false, velocity: 0.8, offset: 0 }));
    this.pushPattern(slot);
    this.showLCD(`PAD ${String(track + 1).padStart(2, '0')}`, 'TRACK ERASED');
    this.markDirty();
  }

  copyPattern() { this.clipboard = structuredClone(this.currentPattern); this.showLCD('COPY', `PATTERN ${slotName(this.project.sequencer.currentPattern)}`); }

  pastePattern() {
    if (!this.clipboard) return;
    const slot = this.project.sequencer.currentPattern;
    const p = normalizePattern(this.clipboard);
    p.name = `Pattern ${slotName(slot)}`;
    this.project.sequencer.patterns[slot] = p;
    this.pushPattern(slot);
    this.showLCD('PASTE', `PATTERN ${slotName(slot)}`);
    this.markDirty();
  }

  quantizeCurrentPattern() {
    const slot = this.project.sequencer.currentPattern;
    const mode = this.project.sequencer.quantize === 'off' ? 'sixteenth' : this.project.sequencer.quantize;
    this.project.sequencer.patterns[slot] = quantizePattern(this.project.sequencer.patterns[slot], mode);
    this.pushPattern(slot);
    this.showLCD('QUANTIZE', QUANTIZE_NAMES[mode]);
    this.markDirty();
  }

  setQuantize(mode) { this.project.sequencer.quantize = mode; this.showLCD('REC QUANTIZE', QUANTIZE_NAMES[mode]); this.markDirty(); }
  toggleMute(t) { this.project.sequencer.trackMutes[t] = !this.project.sequencer.trackMutes[t]; this.sendTrackStates(); this.markDirty(); this.changed(); }
  toggleSolo(t) { this.project.sequencer.trackSolos[t] = !this.project.sequencer.trackSolos[t]; this.sendTrackStates(); this.markDirty(); this.changed(); }

  // ------------------------------------------------------------ Seiten (bis 64 Schritte)

  get pageCount() { return Math.ceil(this.currentPattern.length / STEPS_PER_PAGE); }

  setStepPage(page, follow = false) {
    this.stepPage = Math.min(Math.max(page, 0), PAGE_COUNT - 1);
    this.followPage = follow;
    this.showLCD('PAGE', `${this.stepPage + 1}/${PAGE_COUNT} · STEPS ${this.stepPage * STEPS_PER_PAGE + 1}–${(this.stepPage + 1) * STEPS_PER_PAGE}`, 1);
    this.changed();
  }

  setFollowPage(on) { this.followPage = on; this.changed(); }

  // ------------------------------------------------------------ Song-Modus

  sendSong() {
    const seq = this.project.sequencer;
    this.send({ cmd: 'setSong', chain: seq.songMode && this.project.patternChain.length ? [...this.project.patternChain] : null });
  }

  setSongMode(on) {
    this.project.sequencer.songMode = !!on;
    if (on && !this.project.patternChain.length) this.project.patternChain = [this.project.sequencer.currentPattern];
    this.sendSong();
    this.showLCD('SONG MODE', on ? `ON · ${this.project.patternChain.length} PATTERNS` : 'OFF');
    this.markDirty();
  }

  _songChanged() { if (this.project.sequencer.songMode) this.sendSong(); this.markDirty(); this.changed(); }

  songAppend(slot) {
    if (this.project.patternChain.length >= SONG_MAX_LENGTH) { this.showLCD('SONG', 'FULL (64)'); return; }
    this.project.patternChain.push(slot);
    this.showLCD('SONG', `+ ${slotName(slot)} · ${this.project.patternChain.length}`, 1);
    this._songChanged();
  }

  songRemoveAt(i) { this.project.patternChain.splice(i, 1); this._songChanged(); }

  songMove(i, delta) {
    const c = this.project.patternChain, j = i + delta;
    if (j < 0 || j >= c.length) return;
    [c[i], c[j]] = [c[j], c[i]];
    this._songChanged();
  }

  songSetEntry(i, slot) { if (this.project.patternChain[i] !== undefined) { this.project.patternChain[i] = slot; this._songChanged(); } }

  songClear() { this.project.patternChain = []; this._songChanged(); this.showLCD('SONG', 'CLEARED'); }

  // ------------------------------------------------------------ Motion-Sequenz

  setMotionMode(mode) {
    this.project.sequencer.motionMode = mode;
    this.send({ cmd: 'setMotionMode', mode });
    this.showLCD('MOTION SEQ', MOTION_MODES[mode]);
    this.markDirty();
  }

  /** Zeichnet bei laufender Aufnahme Reglerbewegungen in das hörbare Pattern auf. */
  _recordMotionValue(id, pad) {
    if (!this.isRecording || this.meters.transport !== 'playing' || !canRecordMotion(id)) return;
    const slot = this.meters.currentPattern, step = this.meters.currentStep;
    const pattern = this.project.sequencer.patterns[slot];
    if (!pattern || step >= pattern.length) return;
    const value = getValue(this.project, id, pad);
    const key = `${id}#${PARAMS[id].pad ? pad : -1}`;
    const now = performance.now();
    const last = this._motionLast;
    const from = last && last.key === key && last.slot === slot && step > last.step && now - last.time < 600 ? last : null;
    if (!recordMotion(pattern, id, pad, step, value, from?.step ?? null, from?.value ?? null)) {
      if (!this._motionFullShown) { this.showLCD('MOTION', `FULL (${pattern.motion.length} LANES)`); this._motionFullShown = true; }
      return;
    }
    this._motionFullShown = false;
    this._motionLast = { key, slot, step, value, time: now };
    if (!this._motionPushTimer) {
      this._motionPushTimer = setTimeout(() => { this._motionPushTimer = null; this.pushPattern(slot); }, 40);
    }
    this.markDirty();
  }

  hasMotion(id, pad = this.selectedPad) { return hasMotion(this.currentPattern, id, pad); }

  removeMotionLane(index) {
    const slot = this.project.sequencer.currentPattern;
    const lane = this.currentPattern.motion[index];
    if (!lane) return;
    this.currentPattern.motion.splice(index, 1);
    this.pushPattern(slot);
    this.showLCD('MOTION ERASED', motionLaneName(lane));
    this.markDirty(); this.changed();
  }

  clearMotion() {
    const slot = this.project.sequencer.currentPattern;
    this.currentPattern.motion = [];
    this.pushPattern(slot);
    this.showLCD(`PATTERN ${slotName(slot)}`, 'MOTION CLEARED');
    this.markDirty(); this.changed();
  }

  // ------------------------------------------------------------ Slice

  /**
   * Zerlegt das Sample des ausgewählten Pads und verteilt die Slices ab `startPad` auf die Pads.
   * @param {{ mode: 'equal'|'transients', count?: number, sensitivity?: number, startPad?: number, makePattern?: boolean }} o
   */
  sliceSelectedPad(o) {
    const src = this.selectedPad;
    const sample = this.padSamples[src];
    if (!sample) { this.showLCD('SLICE', 'PAD IS EMPTY'); return 0; }
    const startPad = Math.min(Math.max(o.startPad ?? src, 0), 15);
    const st = { ...this.project.pads[src].settings };
    const parts = this.previewSlices(o);
    if (!parts.length) return 0;
    const srcPad = structuredClone(this.project.pads[src]);
    const source = this.padSources[src];
    const base = srcPad.name.replace(/\s+\d+$/, '').slice(0, 10) || 'SLICE';
    parts.forEach((part, i) => {
      const t = startPad + i;
      const pad = this.project.pads[t];
      pad.name = `${base} ${i + 1}`.slice(0, 14);
      pad.settings = { ...st, start: part.start, end: part.end, reverse: false, playMode: st.playMode === 'loop' ? 'oneShot' : st.playMode };
      pad.sample = srcPad.sample ? { ...srcPad.sample } : undefined;
      if (!pad.sample) delete pad.sample;
      this._setPadSample(t, sample, source);
      this.send({ cmd: 'setPadSettings', pad: t, settings: pad.settings });
    });
    if (o.makePattern) {
      const slot = this.project.sequencer.currentPattern;
      const p = this.project.sequencer.patterns[slot];
      const steps = slicePatternSteps(parts, p.length);
      parts.forEach((_, i) => {
        const t = startPad + i;
        p.steps[t] = Array.from({ length: MAX_STEPS }, () => ({ active: false, velocity: 0.8, offset: 0 }));
        p.steps[t][steps[i]] = { active: true, velocity: 0.8, offset: 0 };
      });
      this.pushPattern(slot);
    }
    this.selectedPad = startPad;
    this.showLCD('SLICE', `${parts.length} SLICES → PAD ${startPad + 1}–${startPad + parts.length}`, 2.5);
    this.markDirty(); this.changed();
    return parts.length;
  }

  /** Slices, die `sliceSelectedPad` mit diesen Einstellungen erzeugen würde (für die Vorschau). */
  previewSlices(o) {
    const src = this.selectedPad;
    const sample = this.padSamples[src];
    if (!sample) return [];
    const startPad = Math.min(Math.max(o.startPad ?? src, 0), 15);
    const available = 16 - startPad;
    const st = this.project.pads[src].settings;
    const mode = o.mode === 'equal'
      ? { type: 'equal', count: Math.min(o.count ?? 8, available) }
      : { type: 'transients', sensitivity: o.sensitivity ?? 0.5, maxSlices: available };
    return computeSlices(sample.left, sample.stereo ? sample.right : null, sample.sampleRate, mode, st.start, st.end).slice(0, available);
  }

  // ------------------------------------------------------------ Sampling & Resampling

  async refreshInputDevices() {
    this.sampling.devices = await this.audio.inputDevices();
    this.changed();
  }

  setSampling(patch) { Object.assign(this.sampling, patch); this.changed(); }

  async startSampling() {
    if (this.sampling.active) return;
    const o = this.sampling;
    const recorder = new SampleRecorder(this.audio.sampleRate, { thresholdDb: o.thresholdDb, maxSeconds: o.maxSeconds });
    try {
      this._capture = await this.audio.startCapture({ source: o.source, deviceId: o.deviceId, monitor: o.monitor }, (l, r) => {
        recorder.append(l, r);
        o.level = recorder.level; o.seconds = recorder.recordedSeconds; o.state = recorder.state;
        if (recorder.state === 'finished') this.stopSampling();
      });
    } catch (err) {
      this.report('Aufnahme nicht möglich', o.source === 'input'
        ? `Auf das Mikrofon bzw. den Audio-Eingang konnte nicht zugegriffen werden (${err.message ?? err}). Prüfen Sie in den Windows-Einstellungen unter Datenschutz → Mikrofon, ob Desktop-Apps zugreifen dürfen.`
        : String(err.message ?? err));
      return;
    }
    this._recorder = recorder;
    o.active = true; o.state = recorder.state; o.level = 0; o.seconds = 0;
    if (o.source === 'output' && o.startPlayback && this.meters.transport !== 'playing') {
      this.send({ cmd: 'transport', transport: 'stop' });
      this.send({ cmd: 'transport', transport: 'play' });
    }
    this.showLCD(o.source === 'input' ? 'SAMPLING' : 'RESAMPLING', recorder.state === 'armed' ? 'WAITING FOR SIGNAL' : 'RECORDING', 2);
    this.changed();
  }

  async stopSampling() {
    const o = this.sampling;
    if (!o.active) return;
    o.active = false;
    const cap = this._capture; this._capture = null;
    await cap?.stop();
    const rec = this._recorder; this._recorder = null;
    if (o.source === 'output' && o.startPlayback) this.send({ cmd: 'transport', transport: 'stop' });
    const n = (this._recCount = (this._recCount ?? 0) + 1);
    const name = `${o.source === 'input' ? 'REC' : 'RESAMPLE'} ${String(n).padStart(2, '0')}`;
    const sample = rec?.finish(name);
    o.state = 'idle'; o.level = 0;
    if (!sample) { this.showLCD('SAMPLING', 'NOTHING RECORDED'); this.changed(); return; }
    await this._assignNewSample(o.targetPad, sample, name);
  }

  /** Rendert das aktuelle Pattern (ein Durchlauf, ohne Ausklang) und legt es als neues Sample auf ein Pad. */
  resamplePattern(targetPad = this.sampling.targetPad) {
    if (this.resampling) return Promise.resolve(null);
    const slot = this.project.sequencer.currentPattern;
    const request = {
      sampleRate: this.audio.sampleRate, project: structuredClone(this.project), samples: this.padSamples,
      patternOrder: [slot], loops: 1, tailSeconds: 0
    };
    this.resampling = true; this.showLCD('RESAMPLE', `PATTERN ${slotName(slot)} …`, 3); this.changed();
    return new Promise((resolve) => {
      const worker = new Worker(new URL('../engine/export-worker.js', import.meta.url), { type: 'module' });
      const done = (v) => { worker.terminate(); this.resampling = false; this.changed(); resolve(v); };
      worker.onmessage = async (e) => {
        const m = e.data;
        if (m.type === 'progress') return;
        if (m.type === 'error') { this.report('Resampling fehlgeschlagen', m.message); done(null); return; }
        const name = `PTN ${slotName(slot)} RESMP`;
        const sample = makeSample([m.left, m.right], m.sampleRate, name);
        await this._assignNewSample(targetPad, sample, name);
        done(sample);
      };
      worker.onerror = (err) => { this.report('Resampling fehlgeschlagen', err.message ?? 'Worker-Fehler'); done(null); };
      worker.postMessage({ request, settings: { raw: true, normalize: false } });
    });
  }

  async _assignNewSample(pad, sample, name) {
    const p = this.project.pads[pad];
    p.name = name.slice(0, 14);
    p.settings = { ...defaultPadSettings(), ...p.settings, start: 0, end: 1, reverse: false };
    p.sample = { fileName: `${name}.wav`, frameCount: sample.frameCount, sampleRate: sample.sampleRate };
    this._setPadSample(pad, sample, { type: 'buffer', sample });
    this.send({ cmd: 'setPadSettings', pad, settings: p.settings });
    this.selectedPad = pad;
    this.showLCD(`PAD ${String(pad + 1).padStart(2, '0')} ← ${name}`, `${sample.frameCount ? (sample.frameCount / sample.sampleRate).toFixed(2) : 0}s ${sample.stereo ? 'ST' : 'MONO'}`, 2.5);
    this.markDirty(); this.changed();
  }

  // ------------------------------------------------------------ Projekte

  async confirmDiscard() {
    if (!this.dirty) return true;
    const r = await bridge.message({
      type: 'question', title: 'NEXORA Sampler', message: `Änderungen an „${this.project.name}“ sichern?`,
      detail: 'Nicht gesicherte Änderungen gehen sonst verloren.', buttons: ['Sichern', 'Nicht sichern', 'Abbrechen'], defaultId: 0, cancelId: 2
    });
    if (r === 0) return this.saveProject();
    return r === 1;
  }

  /** Neues Projekt: `kind` = 'empty' oder 'factory'; ohne Angabe wird gefragt. */
  async newProject(kind) {
    if (!kind) {
      const r = await bridge.message({
        type: 'question', title: 'Neues Projekt', message: 'Wie soll das neue Projekt beginnen?',
        detail: 'Leer: 16 leere Pads und leere Patterns – zum Befüllen mit eigenen Klängen und Songs.\nMit Werks-Kit: das Standard-Kit mit zwei Demo-Beats.',
        buttons: ['Leeres Projekt', 'Mit Werks-Kit', 'Abbrechen'], defaultId: 0, cancelId: 2
      });
      if (r !== 0 && r !== 1) return;
      kind = r === 0 ? 'empty' : 'factory';
    }
    if (!(await this.confirmDiscard())) return;
    this.send({ cmd: 'transport', transport: 'stop' }); this.send({ cmd: 'allNotesOff' });
    this.project = newProject('Untitled');
    this.projectPath = null; this.isRecording = false;
    if (kind === 'factory') {
      await this.loadClassicKit(true);
    } else {
      for (let i = 0; i < 16; i++) this._setPadSample(i, null, null);
      this.pushFullState();
    }
    this.dirty = false; this._updateTitle();
    this.showLCD('NEW PROJECT', kind === 'factory' ? this.project.kitName.toUpperCase() : 'EMPTY');
    this.changed();
  }

  async openProjectWithDialog() {
    if (!(await this.confirmDiscard())) return;
    const p = await bridge.openProject();
    if (p) await this.openProject(p, false);
  }

  async openProject(path, ask = true) {
    if (ask && !(await this.confirmDiscard())) return;
    let loaded;
    try { loaded = await readProject(path); } catch (err) { this.report('Projekt konnte nicht geöffnet werden', err.message ?? String(err)); return; }
    this.send({ cmd: 'transport', transport: 'stop' }); this.send({ cmd: 'allNotesOff' });
    this.isRecording = false;
    this.project = loaded.project;
    this.projectPath = loaded.dir;
    for (let i = 0; i < 16; i++) this._setPadSample(i, null, null);
    this.pushFullState();
    const missing = await this._loadPadSamples(this.project.pads, loaded.dir);
    this.dirty = false; this._updateTitle();
    this.showLCD('PROJECT', this.project.name.toUpperCase());
    if (missing.length) this.report('Fehlende Samples', `Folgende Samples wurden nicht gefunden und können über den Sample-Browser neu zugewiesen werden:\n${missing.join('\n')}`);
  }

  async _loadPadSamples(pads, packageDir) {
    const missing = [];
    const roots = [this.library.root, packageDir ? join(packageDir, '..') : null, this.info.music];
    this.loadingPads = new Set(pads.filter((p) => p.sample).map((p) => p.index)); this.changed();
    for (const pad of pads) {
      if (!pad.sample) continue;
      try {
        const loc = await resolveSample(pad.sample, packageDir, this.library, roots);
        if (!loc) { missing.push(`Pad ${String(pad.index + 1).padStart(2, '0')}: ${pad.sample.fileName}`); continue; }
        if (loc.path) {
          const sample = await this.audio.decode(await bridge.read(loc.path), stem(loc.path));
          this._setPadSample(pad.index, sample, { type: 'file', path: loc.path });
        } else {
          const bytes = await this.library.bytes(loc.item);
          const sample = await this.audio.decode(bytes, loc.item.name);
          this._setPadSample(pad.index, sample, { type: 'bytes', bytes, ext: 'wav', name: loc.item.name });
        }
      } catch { missing.push(`Pad ${String(pad.index + 1).padStart(2, '0')}: ${pad.sample.fileName}`); }
      this.loadingPads.delete(pad.index); this.changed();
    }
    this.loadingPads.clear();
    return missing;
  }

  _sources() {
    return this.padSources.map((src, i) => {
      if (!this.padSamples[i]) return null;
      if (src?.type === 'file' || src?.type === 'bytes') return src;
      return { type: 'buffer', sample: this.padSamples[i] };
    });
  }

  async saveProject() {
    if (!this.projectPath) return this.saveProjectAs();
    return this._writeProject(this.projectPath);
  }

  async saveProjectAs() {
    const target = await bridge.saveProject({ defaultName: this.project.name === 'Untitled' ? 'Mein Beat' : this.project.name });
    if (!target) return false;
    this.project.name = stem(target);
    return this._writeProject(target);
  }

  async _writeProject(target) {
    try {
      const saved = await writeProject(target, this.project, this._sources());
      this.project.pads = saved.pads;
      this.project.modifiedAt = saved.modifiedAt;
      this.projectPath = target;
      saved.pads.forEach((p, i) => { if (p.sample?.packagePath) this.padSources[i] = { type: 'file', path: join(target, ...p.sample.packagePath.split('/')) }; });
      this.dirty = false; this._updateTitle();
      this.showLCD('SAVED', this.project.name.toUpperCase());
      return true;
    } catch (err) {
      this.report('Speichern fehlgeschlagen', err.message ?? String(err));
      return false;
    }
  }

  // ------------------------------------------------------------ Bibliothek

  get visibleItems() {
    const q = this.searchText.trim().toLowerCase();
    if (q) return this.library.collections.flatMap((c) => c.items).filter((i) => i.name.toLowerCase().includes(q));
    return this.library.collection(this.selectedCollection)?.items ?? [];
  }

  async _probe(bytes, name) {
    const s = await this.audio.decode(bytes, name);
    return { duration: s.frameCount / s.sampleRate, sampleRate: s.sampleRate, channels: s.stereo ? 2 : 1 };
  }

  _userTarget() {
    const c = this.library.collection(this.selectedCollection);
    return c && !c.isFactory ? c.id : this.library.userCollections[0].id;
  }

  async importWithDialog() {
    const paths = await bridge.openFiles({ kind: 'audio', multi: true, title: 'Audiodateien in die Bibliothek importieren' });
    if (paths.length) await this.importPaths(paths);
  }

  async importPaths(paths) {
    const r = await this.library.importFiles(paths, this._userTarget(), this.prefs.copyImports, (b, n) => this._probe(b, n));
    this._afterImport(r);
  }

  async importDropped(dataTransfer) {
    const files = [...(dataTransfer.files ?? [])];
    const paths = files.map((f) => bridge.pathForFile?.(f)).filter(Boolean);
    if (paths.length) return this.importPaths(paths);
    const r = await this.library.importBlobs(files.filter((f) => isAudioPath(f.name)), this._userTarget(), (b, n) => this._probe(b, n));
    this._afterImport(r);
  }

  _afterImport(r) {
    if (r.imported.length) { this.selectedCollection = r.collection.id; this.selectedItem = r.imported.at(-1).id; this.showLCD('IMPORTED', `${r.imported.length} SAMPLE(S)`); }
    if (r.failed.length) this.report('Import teilweise fehlgeschlagen', `Nicht importiert:\n${r.failed.join('\n')}`);
    this.libraryRevision++;
    this.drawer = 'browser';
    this.changed();
  }

  // ------------------------------------------------------------ Kits & Presets

  async saveKit(name) {
    const n = name.trim();
    if (!n) return;
    try {
      await this.presets.saveKit(n, this.project.pads, this._sources());
      this.project.kitName = n; this.presetRevision++;
      this.showLCD('KIT SAVED', n.toUpperCase()); this.markDirty();
    } catch (err) { this.report('Kit konnte nicht gespeichert werden', err.message ?? String(err)); }
  }

  async loadKit(info) {
    try {
      const kit = await this.presets.loadKit(info);
      for (const pad of kit.pads) {
        Object.assign(this.project.pads[pad.index], { name: pad.name, settings: pad.settings, sample: pad.sample, keyboardKey: pad.keyboardKey || DEFAULT_KEYS[pad.index] });
        if (!pad.sample) delete this.project.pads[pad.index].sample;
        this._setPadSample(pad.index, null, null);
        this.send({ cmd: 'setPadSettings', pad: pad.index, settings: pad.settings });
      }
      this.project.kitName = kit.name;
      const missing = await this._loadPadSamples(kit.pads, kit.dir);
      if (missing.length) this.report('Fehlende Samples im Kit', missing.join('\n'));
      this.showLCD('KIT', kit.name.toUpperCase()); this.markDirty();
    } catch (err) { this.report('Kit konnte nicht geladen werden', err.message ?? String(err)); }
  }

  async deletePreset(info) { await this.presets.remove(info); this.presetRevision++; this.changed(); }

  async saveEffectPreset(name) {
    if (!name.trim()) return;
    await this.presets.saveEffects(name.trim(), this.project.master);
    this.presetRevision++; this.showLCD('FX PRESET SAVED', name.trim().toUpperCase());
  }

  async loadEffectPreset(info) {
    const p = await this.presets.loadEffects(info);
    this.updateMaster((m) => Object.assign(m, p.master));
    this.showLCD('FX PRESET', p.name.toUpperCase());
  }

  async savePatternPreset(name) {
    if (!name.trim()) return;
    await this.presets.savePattern(name.trim(), this.currentPattern, this.project.bpm, this.project.swing);
    this.presetRevision++; this.showLCD('PATTERN SAVED', name.trim().toUpperCase());
  }

  async loadPatternPreset(info) {
    const p = await this.presets.loadPattern(info);
    const slot = this.project.sequencer.currentPattern;
    this.project.sequencer.patterns[slot] = p.pattern;
    this.project.bpm = p.bpm; this.project.swing = p.swing;
    this.pushPattern(slot);
    this.send({ cmd: 'setTempo', bpm: p.bpm, swing: p.swing });
    this.showLCD(`PATTERN ${slotName(slot)}`, p.name.toUpperCase()); this.markDirty();
  }

  // ------------------------------------------------------------ MIDI

  _onMIDI(m) {
    this.meters.midiActivityUntil = performance.now() + 120;
    if (!this.prefs.midiEnabled) return;
    const midi = this.project.midi;
    const accepts = (ch) => midi.inputChannel === 0 || midi.inputChannel === ch;
    if (m.type === 'noteOn' && accepts(m.channel)) {
      if (this.noteLearnPad != null) { this.assignNote(m.note, this.noteLearnPad); this.noteLearnPad = null; return; }
      const pad = midi.padNotes.indexOf(m.note);
      if (pad >= 0) {
        this.send({ cmd: 'noteOn', pad, velocity: midi.fixedVelocity ? 1 : m.velocity / 127 });
        if (this.prefs.selectOnHit && this.padMode === 'play') this.selectedPad = pad;
      }
    } else if (m.type === 'noteOff' && accepts(m.channel)) {
      const pad = midi.padNotes.indexOf(m.note);
      if (pad >= 0) this.send({ cmd: 'noteOff', pad });
    } else if (m.type === 'cc') {
      if (this.midiLearnActive && this.learnTarget) {
        midi.ccMappings = midi.ccMappings.filter((x) => !(x.controller === m.controller && x.channel === m.channel) && x.parameter !== this.learnTarget);
        midi.ccMappings.push({ id: crypto.randomUUID().toUpperCase(), channel: m.channel, controller: m.controller, parameter: this.learnTarget });
        this.showLCD('MIDI LEARN', `CC${m.controller} CH${m.channel} → ${PARAMS[this.learnTarget].short}`, 2.5);
        this.learnTarget = null; this.markDirty();
        return;
      }
      if (!accepts(m.channel)) return;
      for (const map of midi.ccMappings) {
        if (map.controller === m.controller && (map.channel === 0 || map.channel === m.channel)) this.setParameter(map.parameter, m.value / 127, map.padIndex ?? null);
      }
    } else if (midi.respondToTransport) {
      if (m.type === 'start' || m.type === 'continue') this.play();
      if (m.type === 'stop') this.stop();
    }
    this.changed();
  }

  toggleMIDILearn() {
    this.midiLearnActive = !this.midiLearnActive;
    this.learnTarget = null; this.noteLearnPad = null;
    this.showLCD('MIDI LEARN', this.midiLearnActive ? 'TOUCH A KNOB, MOVE A CC' : 'OFF', 2.5);
  }

  beginLearn(id) { this.midiLearnActive = true; this.learnTarget = id; this.showLCD('MIDI LEARN', `${PARAMS[id].short}: MOVE A CONTROLLER`, 3); }
  mappingFor(id) { return this.project.midi.ccMappings.find((m) => m.parameter === id) ?? null; }
  removeMapping(id) { this.project.midi.ccMappings = this.project.midi.ccMappings.filter((m) => m.parameter !== id && m.id !== id); this.markDirty(); this.changed(); }

  assignNote(note, pad) {
    const notes = this.project.midi.padNotes;
    for (let i = 0; i < 16; i++) if (notes[i] === note && i !== pad) notes[i] = -1;
    notes[pad] = Math.min(Math.max(note, 0), 127);
    this.showLCD(`PAD ${String(pad + 1).padStart(2, '0')} NOTE`, noteName(note));
    this.markDirty();
  }

  // ------------------------------------------------------------ Export

  async exportAudio(settings) {
    this.project.export = { ...settings };
    this.markDirty();
    const kind = settings.format === 'wav' ? 'wav' : 'aiff';
    const name = `${this.project.name} - ${settings.exportChain ? 'Chain' : `Pattern ${slotName(this.project.sequencer.currentPattern)}`}.${settings.format === 'wav' ? 'wav' : 'aif'}`;
    const target = await bridge.saveFile({ defaultName: name, kind, title: 'Audio exportieren' });
    if (!target) return null;
    return this.renderExport(settings, target);
  }

  /** Rendert im Worker; schreibt nach `target` (falls angegeben) und liefert die Dateidaten. */
  renderExport(settings, target = null) {
    const order = settings.exportChain ? this.project.patternChain : [this.project.sequencer.currentPattern];
    const request = {
      sampleRate: settings.sampleRate, project: structuredClone(this.project), samples: this.padSamples,
      patternOrder: order, loops: settings.loops, tailSeconds: settings.tailSeconds
    };
    this.exportProgress = 0; this.changed();
    return new Promise((resolve) => {
      const worker = new Worker(new URL('../engine/export-worker.js', import.meta.url), { type: 'module' });
      this._exportWorker = worker;
      const finish = (value) => { worker.terminate(); this._exportWorker = null; this.exportProgress = null; this.changed(); resolve(value); };
      worker.onmessage = async (e) => {
        const m = e.data;
        if (m.type === 'progress') { this.exportProgress = m.value; this.changed(); return; }
        if (m.type === 'error') { this.report('Export fehlgeschlagen', m.message); finish(null); return; }
        try {
          if (target) { await bridge.write(target, m.data); bridge.showInFolder(target); }
          this.showLCD('EXPORTED', `${target ? basename(target).toUpperCase() : 'AUDIO'} ${m.duration.toFixed(1)}s`, 3);
          this.dialog = null;
          finish({ data: m.data, duration: m.duration });
        } catch (err) { this.report('Export fehlgeschlagen', err.message ?? String(err)); finish(null); }
      };
      worker.onerror = (err) => { this.report('Export fehlgeschlagen', err.message ?? 'Worker-Fehler'); finish(null); };
      worker.postMessage({ request, settings });
    });
  }

  cancelExport() {
    if (this._exportWorker) {
      this._exportWorker.terminate();
      this._exportWorker = null;
      this.exportProgress = null;
      this.showLCD('EXPORT', 'CANCELLED');
    }
  }

  // ------------------------------------------------------------ Tastatur & Menü

  handleKey(e, down) {
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return false;
    if (e.ctrlKey || e.metaKey || e.altKey) return false;
    if (document.querySelector('.modal-backdrop')) return false;
    const key = e.key.toLowerCase();
    if (key === ' ') { if (down && !e.repeat) this.togglePlay(); return true; }
    const pad = this.project.pads.findIndex((p) => p.keyboardKey === key);
    if (pad < 0) return false;
    if (e.repeat) return true;
    if (down) this.padDown(pad, this.prefs.keyboardVelocity); else this.padUp(pad);
    return true;
  }

  menu(id) {
    const [cmd, arg] = id.split(':');
    const actions = {
      new: () => this.newProject(arg), open: () => this.openProjectWithDialog(), save: () => this.saveProject(), saveAs: () => this.saveProjectAs(),
      import: () => this.importWithDialog(), loadSample: () => this.chooseSampleForSelectedPad(),
      export: () => { this.dialog = 'export'; this.changed(); }, settings: () => { this.dialog = 'settings'; this.changed(); },
      togglePlay: () => this.togglePlay(), pause: () => this.pause(), record: () => this.toggleRecord(),
      metronome: () => this.toggleMetronome(), tap: () => this.tapTempo(), pattern: () => this.selectPattern(Number(arg)),
      mode: () => this.setPadMode(arg), octave: () => { this.keyboardOctave = Math.max(-3, Math.min(3, this.keyboardOctave + Number(arg))); this.showLCD('KEYBOARD', `OCT ${this.keyboardOctave}`); },
      drawer: () => { this.drawer = arg === 'none' ? null : arg; this.changed(); }, learn: () => this.toggleMIDILearn(),
      panic: () => this.send({ cmd: 'allNotesOff' }),
      page: () => this.setStepPage(this.stepPage + Number(arg)),
      slice: () => { this.dialog = 'slice'; this.changed(); },
      resample: () => this.resamplePattern(this.selectedPad),
      song: () => this.setSongMode(!this.project.sequencer.songMode), openPath: () => this.openProject(id.slice('openPath:'.length))
    };
    actions[cmd]?.();
  }
}

export { FACTORY_PREFIX, slotName, PARAMS, PATTERN_SLOTS, MAX_STEPS, QUANTIZE_NAMES, noteName, defaultMaster };
