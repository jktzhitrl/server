// NEXORA Sampler – Datenmodell. Feldnamen und Standardwerte entsprechen exakt dem Swift-Kern
// (NexoraCore/Models), sodass Projekte (.nexora) zwischen Mac und Windows austauschbar sind.

import { clamp } from './dsp.js';

export const PAD_COUNT = 16;
export const PATTERN_SLOTS = 8;
export const MAX_STEPS = 64;
export const STEPS_PER_PAGE = 16;
export const PAGE_COUNT = MAX_STEPS / STEPS_PER_PAGE;
export const MOTION_MAX_LANES = 24;
export const SONG_MAX_LENGTH = 64;
export const TRACKS = 16;
export const FORMAT_VERSION = 1;

export const defaultPadSettings = () => ({
  volume: 0.8, pan: 0, pitch: 0, fineTune: 0, speed: 1, pitchMode: 'varispeed',
  start: 0, end: 1, reverse: false, playMode: 'oneShot',
  attack: 0.001, decay: 0.4, sustain: 1, release: 0.08,
  filterMode: 'off', cutoff: 18000, resonance: 0.1, filterEnvAmount: 0,
  lfoRate: 4, lfoDepth: 0, lfoShape: 'sine', lfoTarget: 'off',
  insertFXOn: true, drive: 0, crushBits: 16, crushDownsample: 1,
  reverbSend: 1, delaySend: 1, velocitySensitivity: 0.7, chokeGroup: 0, mono: false
});

export const defaultMaster = () => ({
  volume: 0.8, filterMode: 'lowPass', filterCutoff: 20000, filterResonance: 0.15,
  drive: 0, crushBits: 16, crushDownsample: 1,
  delayTime: 0.375, delaySync: 'dottedEighth', delayFeedback: 0.35, delayMix: 0, delayPingPong: true, delayDamping: 0.3,
  reverbSize: 0.75, reverbDamping: 0.4, reverbMix: 0, reverbWidth: 1,
  eqLow: 0, eqMid: 0, eqHigh: 0, eqMidFrequency: 1000,
  compThreshold: 0, compRatio: 4, compAttack: 0.01, compRelease: 0.15, compMakeup: 0,
  modRate: 2, modDepth: 0, modShape: 'sine', modTarget: 'filter'
});

export const TEMPO_DIVISIONS = {
  off: null, whole: 4, half: 2, quarter: 1, dottedEighth: 0.75, eighth: 0.5,
  tripletEighth: 1 / 3, sixteenth: 0.25, tripletSixteenth: 1 / 6, thirtySecond: 0.125
};
export const TEMPO_DIVISION_NAMES = {
  off: 'FREE', whole: '1/1', half: '1/2', quarter: '1/4', dottedEighth: '1/8.', eighth: '1/8',
  tripletEighth: '1/8T', sixteenth: '1/16', tripletSixteenth: '1/16T', thirtySecond: '1/32'
};

export function effectiveDelaySeconds(master, bpm) {
  const beats = TEMPO_DIVISIONS[master.delaySync];
  return beats != null && bpm > 0 ? (beats * 60) / bpm : master.delayTime;
}

export const uuid = () => (globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() :
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  })).toUpperCase();

export const slotName = (i) => 'ABCDEFGHIJKLMNOP'[i] ?? String(i + 1);

export const newStep = (active = false, velocity = 0.8, offset = 0) => ({ active, velocity, offset });

export function newPattern(name, length = 16) {
  return {
    id: uuid(), name, length: clamp(length, 1, MAX_STEPS),
    steps: Array.from({ length: TRACKS }, () => Array.from({ length: MAX_STEPS }, () => newStep())),
    gates: Array(TRACKS).fill(1),
    motion: []
  };
}

export const MOTION_MODES = { off: 'AUS', hold: 'STUFEN', smooth: 'GLATT' };

/** Nur Pad- und Master-Parameter lassen sich als Motion aufzeichnen (Tempo/Swing nicht). */
export const canRecordMotion = (id) => !!(PARAMS[id]?.pad || PARAMS[id]?.master);

export function newMotionLane(parameter, pad) {
  return { parameter, pad: PARAMS[parameter]?.pad ? clamp(pad | 0, 0, 15) : -1, values: Array(MAX_STEPS).fill(null) };
}

function normalizeMotionLane(l) {
  if (!l || !canRecordMotion(l.parameter)) return null;
  const spec = PARAMS[l.parameter];
  const lane = newMotionLane(l.parameter, Number(l.pad ?? -1));
  for (let i = 0; i < MAX_STEPS; i++) {
    const v = l.values?.[i];
    lane.values[i] = v == null || !Number.isFinite(Number(v)) ? null : clamp(Number(v), spec.min, spec.max);
  }
  return lane;
}

export function normalizePattern(p) {
  const out = newPattern(typeof p?.name === 'string' ? p.name : 'Pattern', Number.isFinite(p?.length) ? p.length : 16);
  if (typeof p?.id === 'string') out.id = p.id;
  for (let t = 0; t < TRACKS; t++) {
    for (let s = 0; s < MAX_STEPS; s++) {
      const st = p?.steps?.[t]?.[s];
      if (st) out.steps[t][s] = newStep(!!st.active, clamp(Number(st.velocity ?? 0.8), 0, 1), clamp(Number(st.offset ?? 0), -0.5, 0.499));
    }
    const g = Number(p?.gates?.[t]);
    out.gates[t] = Number.isFinite(g) ? clamp(g, 0.05, 16) : 1;
  }
  const seen = new Set();
  for (const raw of Array.isArray(p?.motion) ? p.motion : []) {
    const lane = normalizeMotionLane(raw);
    if (!lane) continue;
    const key = `${lane.parameter}#${lane.pad}`;
    if (seen.has(key) || out.motion.length >= MOTION_MAX_LANES) continue;
    seen.add(key);
    out.motion.push(lane);
  }
  return out;
}

/** Anzahl der zu speichernden Schritte: Länge bzw. letzter aktiver Schritt, auf ganze Seiten gerundet. */
export function storedStepCount(p) {
  let last = p.length - 1;
  for (const track of p.steps) for (let i = track.length - 1; i > last; i--) if (track[i].active) { last = i; break; }
  const pages = Math.floor((last + STEPS_PER_PAGE) / STEPS_PER_PAGE);
  return Math.min(MAX_STEPS, Math.max(1, pages) * STEPS_PER_PAGE);
}

/** Kompakte Form zum Speichern – identisch zur Kodierung im Swift-Kern. */
export function compactPattern(p) {
  const n = storedStepCount(p);
  const out = { id: p.id, name: p.name, length: p.length, steps: p.steps.map((t) => t.slice(0, n)), gates: p.gates };
  if (p.motion?.length) {
    out.motion = p.motion.map((l) => {
      let last = -1;
      l.values.forEach((v, i) => { if (v != null) last = i; });
      return { parameter: l.parameter, pad: l.pad, values: l.values.slice(0, last + 1) };
    });
  }
  return out;
}

export function compactProject(project) {
  return { ...project, sequencer: { ...project.sequencer, patterns: project.sequencer.patterns.map(compactPattern) } };
}

export function motionLaneIndex(pattern, parameter, pad) {
  const p = PARAMS[parameter]?.pad ? pad : -1;
  return pattern.motion.findIndex((l) => l.parameter === parameter && l.pad === p);
}

export const hasMotion = (pattern, parameter, pad) => motionLaneIndex(pattern, parameter, pad) >= 0;

/**
 * Zeichnet einen Motion-Wert auf. Liegt `fromStep` vor `step` (gleicher Durchlauf), werden die
 * Schritte dazwischen linear aufgefüllt. Liefert false, wenn keine Spur mehr frei ist.
 */
export function recordMotion(pattern, parameter, pad, step, value, fromStep = null, fromValue = null) {
  if (!canRecordMotion(parameter) || step < 0 || step >= MAX_STEPS) return false;
  let i = motionLaneIndex(pattern, parameter, pad);
  if (i < 0) {
    if (pattern.motion.length >= MOTION_MAX_LANES) return false;
    pattern.motion.push(newMotionLane(parameter, pad));
    i = pattern.motion.length - 1;
  }
  const spec = PARAMS[parameter];
  const v = clamp(value, spec.min, spec.max);
  const lane = pattern.motion[i];
  if (fromStep != null && fromValue != null && fromStep < step && step - fromStep <= MAX_STEPS / 2) {
    for (let s = fromStep + 1; s < step; s++) lane.values[s] = fromValue + ((v - fromValue) * (s - fromStep)) / (step - fromStep);
  }
  lane.values[step] = v;
  return true;
}

export function removeMotion(pattern, parameter, pad) {
  const i = motionLaneIndex(pattern, parameter, pad);
  if (i >= 0) pattern.motion.splice(i, 1);
}

export const motionLaneName = (l) => (l.pad >= 0 ? `PAD ${String(l.pad + 1).padStart(2, '0')} ${PARAMS[l.parameter].short}` : `MASTER ${PARAMS[l.parameter].short}`);

/** Füllt Lücken einer Motion-Spur zyklisch auf: Stufen (`hold`) bzw. linear (`smooth`). */
export function fillMotion(values) {
  const n = values.length;
  const defined = [];
  values.forEach((v, i) => { if (v != null) defined.push(i); });
  if (!defined.length) return { hold: [], smooth: [] };
  const hold = new Array(n), smooth = new Array(n);
  for (let s = 0; s < n; s++) {
    let prev = defined[defined.length - 1];
    for (const d of defined) if (d <= s) prev = d;
    let next = defined[0];
    for (const d of defined) if (d > s) { next = d; break; }
    const pv = values[prev], nv = values[next];
    hold[s] = pv;
    if (prev === s || prev === next) smooth[s] = pv;
    else {
      const span = ((next - prev) % n + n) % n;
      const pos = ((s - prev) % n + n) % n;
      smooth[s] = pv + ((nv - pv) * pos) / Math.max(span, 1);
    }
  }
  return { hold, smooth };
}

export const DEFAULT_KEYS = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k'];

export const defaultMIDI = () => ({
  inputChannel: 0, padNotes: Array.from({ length: 16 }, (_, i) => 36 + i), ccMappings: [],
  respondToTransport: true, fixedVelocity: false
});

export const defaultExport = () => ({
  format: 'wav', sampleRate: 44100, bitDepth: 'pcm24', loops: 2, tailSeconds: 3, exportChain: false, normalize: false
});

export function newProject(name = 'Untitled') {
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  return {
    format: 'de.nexora.sampler.project', formatVersion: FORMAT_VERSION, name, kitName: 'Empty Kit',
    createdAt: now, modifiedAt: now, bpm: 120, swing: 50,
    pads: Array.from({ length: 16 }, (_, i) => ({ index: i, name: `PAD ${i + 1}`, settings: defaultPadSettings(), keyboardKey: DEFAULT_KEYS[i] })),
    master: defaultMaster(),
    engine: { polyphony: 32, stealMode: 'oldest' },
    sequencer: {
      patterns: Array.from({ length: PATTERN_SLOTS }, (_, i) => newPattern(`Pattern ${slotName(i)}`)),
      currentPattern: 0, quantize: 'sixteenth', metronome: false, switchAtBarEnd: true,
      trackMutes: Array(16).fill(false), trackSolos: Array(16).fill(false),
      motionMode: 'hold', songMode: false
    },
    xyPad: { xParameter: 'masterFilterCutoff', yParameter: 'reverbMix' },
    midi: defaultMIDI(),
    export: defaultExport(),
    patternChain: [0]
  };
}

const merge = (defaults, value) => {
  const out = { ...defaults };
  if (value && typeof value === 'object') {
    for (const k of Object.keys(defaults)) {
      if (value[k] !== undefined && typeof value[k] === typeof defaults[k]) out[k] = value[k];
    }
  }
  return out;
};

/** Toleranter Import (fehlende Felder → Standardwerte, unbekannte Felder werden ignoriert). */
export function normalizeProject(raw) {
  if (raw?.formatVersion > FORMAT_VERSION) throw new Error(`Die Projektdatei wurde mit einer neueren Version erstellt (Format ${raw.formatVersion}).`);
  const base = newProject(typeof raw?.name === 'string' ? raw.name : 'Untitled');
  const p = { ...base };
  for (const k of ['name', 'kitName', 'createdAt', 'modifiedAt']) if (typeof raw?.[k] === 'string') p[k] = raw[k];
  p.bpm = clamp(Number(raw?.bpm ?? 120) || 120, 40, 300);
  p.swing = clamp(Number(raw?.swing ?? 50) || 50, 50, 75);
  const byIndex = new Map();
  for (const pad of raw?.pads ?? []) if (Number.isInteger(pad?.index) && pad.index >= 0 && pad.index < 16) byIndex.set(pad.index, pad);
  p.pads = base.pads.map((d, i) => {
    const r = byIndex.get(i);
    if (!r) return d;
    const pad = {
      index: i, name: typeof r.name === 'string' ? r.name : d.name,
      settings: merge(defaultPadSettings(), r.settings),
      keyboardKey: typeof r.keyboardKey === 'string' ? r.keyboardKey : d.keyboardKey
    };
    if (r.sample && typeof r.sample === 'object') pad.sample = r.sample;
    return pad;
  });
  p.master = merge(defaultMaster(), raw?.master);
  p.engine = merge(base.engine, raw?.engine);
  p.engine.polyphony = clamp(p.engine.polyphony, 1, 64);
  const seq = raw?.sequencer ?? {};
  p.sequencer = {
    patterns: Array.from({ length: PATTERN_SLOTS }, (_, i) => seq.patterns?.[i] ? normalizePattern(seq.patterns[i]) : newPattern(`Pattern ${slotName(i)}`)),
    currentPattern: clamp(Number(seq.currentPattern ?? 0) | 0, 0, PATTERN_SLOTS - 1),
    quantize: ['off', 'sixteenth', 'eighth', 'quarter'].includes(seq.quantize) ? seq.quantize : 'sixteenth',
    metronome: !!seq.metronome,
    switchAtBarEnd: seq.switchAtBarEnd !== false,
    trackMutes: Array.from({ length: 16 }, (_, i) => !!seq.trackMutes?.[i]),
    trackSolos: Array.from({ length: 16 }, (_, i) => !!seq.trackSolos?.[i]),
    motionMode: Object.keys(MOTION_MODES).includes(seq.motionMode) ? seq.motionMode : 'hold',
    songMode: !!seq.songMode
  };
  p.xyPad = merge(base.xyPad, raw?.xyPad);
  p.midi = merge(defaultMIDI(), raw?.midi);
  p.midi.padNotes = Array.from({ length: 16 }, (_, i) => clamp(Number(p.midi.padNotes?.[i] ?? 36 + i), -1, 127));
  p.midi.ccMappings = (Array.isArray(p.midi.ccMappings) ? p.midi.ccMappings : []).filter((m) => PARAMS[m?.parameter]);
  p.export = merge(defaultExport(), raw?.export);
  p.patternChain = (Array.isArray(raw?.patternChain) ? raw.patternChain : [0]).filter((s) => Number.isInteger(s) && s >= 0 && s < PATTERN_SLOTS).slice(0, SONG_MAX_LENGTH);
  if (!p.patternChain.length) p.patternChain = [p.sequencer.currentPattern];
  return p;
}

export const muteMask = (flags) => flags.reduce((m, f, i) => (f ? m | (1 << i) : m), 0);

// ---------------------------------------------------------------- Parameter-Registry

const P = (name, short, min, max, def, taper, unit, extra = {}) => ({ name, short, min, max, def, taper, unit, ...extra });

/** Wertebereiche, Kennlinien und Ziele – identisch zu `ParameterID` im Swift-Kern. */
export const PARAMS = {
  padVolume: P('Pad Volume', 'VOLUME', 0, 1.25, 0.8, 'quadratic', 'gain', { pad: 'volume' }),
  padPan: P('Pad Pan', 'PAN', -1, 1, 0, 'linear', 'pan', { pad: 'pan' }),
  padPitch: P('Pad Pitch', 'PITCH', -24, 24, 0, 'linear', 'semitones', { pad: 'pitch', integer: true }),
  padFineTune: P('Fine Tune', 'FINE', -100, 100, 0, 'linear', 'cents', { pad: 'fineTune' }),
  padSpeed: P('Playback Speed', 'SPEED', 0.25, 4, 1, 'exponential', 'factor', { pad: 'speed' }),
  padStart: P('Sample Start', 'START', 0, 1, 0, 'linear', 'percent', { pad: 'start' }),
  padEnd: P('Sample End', 'END', 0, 1, 1, 'linear', 'percent', { pad: 'end' }),
  padAttack: P('Attack', 'ATTACK', 0.0005, 4, 0.001, 'exponential', 'seconds', { pad: 'attack' }),
  padDecay: P('Decay', 'DECAY', 0.005, 8, 0.4, 'exponential', 'seconds', { pad: 'decay' }),
  padSustain: P('Sustain', 'SUSTAIN', 0, 1, 1, 'linear', 'percent', { pad: 'sustain' }),
  padRelease: P('Release', 'RELEASE', 0.002, 8, 0.08, 'exponential', 'seconds', { pad: 'release' }),
  padCutoff: P('Pad Filter Cutoff', 'CUTOFF', 20, 20000, 18000, 'exponential', 'hertz', { pad: 'cutoff' }),
  padResonance: P('Pad Resonance', 'RESO', 0, 1, 0.1, 'linear', 'percent', { pad: 'resonance' }),
  padFilterEnv: P('Filter EG Intensity', 'EG INT', -1, 1, 0, 'linear', 'percent', { pad: 'filterEnvAmount' }),
  padLFORate: P('Pad LFO Rate', 'LFO RATE', 0.05, 30, 4, 'exponential', 'hertz', { pad: 'lfoRate' }),
  padLFODepth: P('Pad LFO Depth', 'LFO AMT', 0, 1, 0, 'linear', 'percent', { pad: 'lfoDepth' }),
  padDrive: P('Pad Drive', 'DRIVE', 0, 1, 0, 'linear', 'percent', { pad: 'drive' }),
  padCrushBits: P('Pad Bit Depth', 'BITS', 1, 16, 16, 'linear', 'bits', { pad: 'crushBits' }),
  padCrushRate: P('Pad Downsample', 'RATE', 1, 32, 1, 'exponential', 'divisor', { pad: 'crushDownsample' }),
  padReverbSend: P('Reverb Send', 'REV SND', 0, 1, 1, 'linear', 'percent', { pad: 'reverbSend' }),
  padDelaySend: P('Delay Send', 'DLY SND', 0, 1, 1, 'linear', 'percent', { pad: 'delaySend' }),
  padVelocitySensitivity: P('Velocity Sensitivity', 'VELO', 0, 1, 0.7, 'linear', 'percent', { pad: 'velocitySensitivity' }),
  masterVolume: P('Master Volume', 'MASTER', 0, 1.25, 0.8, 'quadratic', 'gain', { master: 'volume' }),
  masterFilterCutoff: P('Filter Cutoff', 'FILTER', 20, 20000, 20000, 'exponential', 'hertz', { master: 'filterCutoff' }),
  masterFilterResonance: P('Filter Resonance', 'RESO', 0, 1, 0.15, 'linear', 'percent', { master: 'filterResonance' }),
  masterDrive: P('Distortion', 'DRIVE', 0, 1, 0, 'linear', 'percent', { master: 'drive' }),
  masterCrushBits: P('Bitcrusher Depth', 'BITS', 1, 16, 16, 'linear', 'bits', { master: 'crushBits' }),
  masterCrushRate: P('Bitcrusher Rate', 'CRUSH', 1, 32, 1, 'exponential', 'divisor', { master: 'crushDownsample' }),
  delayTime: P('Delay Time', 'TIME', 0.01, 2, 0.375, 'exponential', 'seconds', { master: 'delayTime' }),
  delayFeedback: P('Delay Feedback', 'FEEDBK', 0, 0.95, 0.35, 'linear', 'percent', { master: 'delayFeedback' }),
  delayMix: P('Delay Mix', 'DELAY', 0, 1, 0, 'linear', 'percent', { master: 'delayMix' }),
  delayDamping: P('Delay Tone', 'D.TONE', 0, 0.95, 0.3, 'linear', 'percent', { master: 'delayDamping' }),
  reverbSize: P('Reverb Size', 'SIZE', 0, 1, 0.75, 'linear', 'percent', { master: 'reverbSize' }),
  reverbDamping: P('Reverb Damping', 'DAMP', 0, 1, 0.4, 'linear', 'percent', { master: 'reverbDamping' }),
  reverbMix: P('Reverb Mix', 'REVERB', 0, 1, 0, 'linear', 'percent', { master: 'reverbMix' }),
  reverbWidth: P('Reverb Width', 'WIDTH', 0, 1, 1, 'linear', 'percent', { master: 'reverbWidth' }),
  eqLow: P('EQ Low', 'LOW', -15, 15, 0, 'linear', 'decibel', { master: 'eqLow' }),
  eqMid: P('EQ Mid', 'MID', -15, 15, 0, 'linear', 'decibel', { master: 'eqMid' }),
  eqHigh: P('EQ High', 'HIGH', -15, 15, 0, 'linear', 'decibel', { master: 'eqHigh' }),
  eqMidFrequency: P('EQ Mid Frequency', 'MID FRQ', 200, 8000, 1000, 'exponential', 'hertz', { master: 'eqMidFrequency' }),
  compThreshold: P('Compressor Threshold', 'COMP', -40, 0, 0, 'linear', 'decibel', { master: 'compThreshold' }),
  compRatio: P('Compressor Ratio', 'RATIO', 1, 20, 4, 'exponential', 'ratio', { master: 'compRatio' }),
  compAttack: P('Compressor Attack', 'C.ATK', 0.0005, 0.2, 0.01, 'exponential', 'seconds', { master: 'compAttack' }),
  compRelease: P('Compressor Release', 'C.REL', 0.01, 2, 0.15, 'exponential', 'seconds', { master: 'compRelease' }),
  compMakeup: P('Compressor Makeup', 'MAKEUP', 0, 24, 0, 'linear', 'decibel', { master: 'compMakeup' }),
  modRate: P('LFO Rate', 'LFO', 0.05, 20, 2, 'exponential', 'hertz', { master: 'modRate' }),
  modDepth: P('Modulation Depth', 'MOD', 0, 1, 0, 'linear', 'percent', { master: 'modDepth' }),
  tempo: P('Tempo', 'TEMPO', 40, 300, 120, 'linear', 'bpm', { project: 'bpm' }),
  swing: P('Swing', 'SWING', 50, 75, 50, 'linear', 'swing', { project: 'swing' })
};

export function fromNormalized(id, n) {
  const s = PARAMS[id];
  const t = clamp(n, 0, 1);
  let v = s.taper === 'exponential' ? s.min * Math.pow(s.max / s.min, t)
    : s.taper === 'quadratic' ? s.min + t * t * (s.max - s.min) : s.min + t * (s.max - s.min);
  if (s.integer) v = Math.round(v);
  return clamp(v, s.min, s.max);
}

export function toNormalized(id, value) {
  const s = PARAMS[id];
  const v = clamp(value, s.min, s.max);
  if (s.max <= s.min) return 0;
  if (s.taper === 'exponential') return Math.log(v / s.min) / Math.log(s.max / s.min);
  if (s.taper === 'quadratic') return Math.sqrt((v - s.min) / (s.max - s.min));
  return (v - s.min) / (s.max - s.min);
}

export function formatValue(id, v) {
  const u = PARAMS[id].unit;
  switch (u) {
    case 'percent': return `${Math.round(v * 100)}%`;
    case 'hertz': return v >= 1000 ? `${(v / 1000).toFixed(2)}k` : `${v.toFixed(0)}Hz`;
    case 'decibel': return `${v >= 0 ? '+' : ''}${v.toFixed(1)}dB`;
    case 'seconds': return v < 1 ? `${(v * 1000).toFixed(0)}ms` : `${v.toFixed(2)}s`;
    case 'semitones': return `${v >= 0 ? '+' : ''}${v.toFixed(0)}st`;
    case 'cents': return `${v >= 0 ? '+' : ''}${v.toFixed(0)}ct`;
    case 'ratio': return `${v.toFixed(1)}:1`;
    case 'bits': return `${v.toFixed(0)}bit`;
    case 'bpm': return v.toFixed(1);
    case 'factor': return `${v.toFixed(2)}x`;
    case 'pan': return Math.abs(v) < 0.01 ? 'C' : v < 0 ? `L${Math.round(-v * 100)}` : `R${Math.round(v * 100)}`;
    case 'gain': return v <= 0.0001 ? '-inf' : `${(20 * Math.log10(v)).toFixed(1)}dB`;
    case 'swing': return `${v.toFixed(0)}%`;
    case 'divisor': return v <= 1.01 ? 'OFF' : `1/${v.toFixed(0)}`;
    default: return String(v);
  }
}

export function getValue(project, id, pad) {
  const s = PARAMS[id];
  if (s.pad) return project.pads[clamp(pad, 0, 15)].settings[s.pad];
  if (s.master) return project.master[s.master];
  return project[s.project];
}

/** Setzt einen Parameter (begrenzt) und liefert den Wirkungsbereich: {pad}, 'master' oder 'tempo'. */
export function setValue(project, id, value, pad) {
  const s = PARAMS[id];
  let v = clamp(value, s.min, s.max);
  if (s.integer) v = Math.round(v);
  if (s.pad) {
    const st = project.pads[clamp(pad, 0, 15)].settings;
    st[s.pad] = v;
    if (id === 'padStart' && st.end < v + 0.001) st.end = Math.min(1, v + 0.001);
    if (id === 'padEnd' && st.start > v - 0.001) st.start = Math.max(0, v - 0.001);
    return { pad: clamp(pad, 0, 15) };
  }
  if (s.master) {
    project.master[s.master] = v;
    if (id === 'delayTime') project.master.delaySync = 'off';
    return 'master';
  }
  project[s.project] = v;
  return 'tempo';
}

// ---------------------------------------------------------------- Quantisierung

export const QUANTIZE_GRID = { off: null, sixteenth: 1, eighth: 2, quarter: 4 };
export const QUANTIZE_NAMES = { off: 'OFF', sixteenth: '1/16', eighth: '1/8', quarter: '1/4' };

export const swingDelay = (step, swing) => (step % 2 === 1 ? (clamp(swing, 50, 75) - 50) / 50 : 0);

export function placeHit(position, length, mode, swing = 50) {
  const len = Math.max(length, 1);
  const grid = QUANTIZE_GRID[mode] ?? 1;
  const rounded = Math.round(position / grid) * grid;
  let step = rounded % len;
  if (step < 0) step += len;
  if (mode !== 'off') return { step, offset: 0 };
  const offset = clamp(position - rounded - swingDelay(step, swing), -0.5, 0.499);
  return { step, offset };
}

export function quantizePattern(pattern, mode) {
  const grid = QUANTIZE_GRID[mode] ?? 1;
  const out = normalizePattern(pattern);
  for (let t = 0; t < TRACKS; t++) {
    const fresh = Array.from({ length: MAX_STEPS }, () => newStep());
    for (let s = 0; s < pattern.length; s++) {
      const st = pattern.steps[t][s];
      if (!st.active) continue;
      let target = Math.round((s + st.offset) / grid) * grid;
      target = ((target % pattern.length) + pattern.length) % pattern.length;
      if (!fresh[target].active || fresh[target].velocity < st.velocity) fresh[target] = newStep(true, st.velocity, 0);
    }
    for (let s = pattern.length; s < MAX_STEPS; s++) fresh[s] = { ...pattern.steps[t][s] };
    out.steps[t] = fresh;
  }
  return out;
}
