import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SamplerEngine, makeSample, patternSnapshot } from '../src/engine/engine.js';
import { defaultPadSettings, defaultMaster, newPattern, newProject, normalizeProject, PARAMS, fromNormalized, toNormalized,
  setValue, getValue, formatValue, placeHit, quantizePattern } from '../src/engine/model.js';
import { encodeAudio, decodeAudio } from '../src/engine/audiofile.js';
import { renderOffline } from '../src/engine/offline.js';

const SR = 44100;
const dc = (v, n) => makeSample([new Float32Array(n).fill(v)], SR);
const neutral = (over = {}) => ({ ...defaultPadSettings(), volume: 1, velocitySensitivity: 0, reverbSend: 0, delaySend: 0, ...over });
function engineWith(sample, settings = neutral()) {
  const e = new SamplerEngine(SR);
  e.setMaster({ ...defaultMaster(), volume: 1 });
  e.setSample(0, sample); e.setPadSettings(0, settings);
  return e;
}
function render(e, frames, block = 256) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  const bl = new Float32Array(block), br = new Float32Array(block);
  for (let d = 0; d < frames; d += block) {
    const n = Math.min(block, frames - d);
    e.render(n, bl, br); L.set(bl.subarray(0, n), d); R.set(br.subarray(0, n), d);
  }
  return { L, R };
}
const lastNonZero = (x) => { for (let i = x.length - 1; i >= 0; i--) if (Math.abs(x[i]) > 1e-5) return i; return -1; };
function onsets(x, gap = 200) {
  const out = []; let silent = gap;
  for (let i = 0; i < x.length; i++) {
    if (Math.abs(x[i]) > 0.001) { if (silent >= gap) out.push(i); silent = 0; } else silent++;
  }
  return out;
}
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg ?? ''} ${a} ≉ ${b} ± ${tol}`);

test('Note-On spielt das Sample, One-Shot endet am Sample-Ende', () => {
  const e = engineWith(dc(0.5, 1000));
  e.noteOn(0, 1);
  const { L } = render(e, 3000);
  near(L[500], 0.5, 0.01);
  near(lastNonZero(L), 1000, 3);
});

test('Start und Ende sind klickfrei', () => {
  const e = engineWith(dc(0.9, 2000));
  e.noteOn(0, 1);
  const { L } = render(e, 3000);
  let max = 0; for (let i = 1; i < L.length; i++) max = Math.max(max, Math.abs(L[i] - L[i - 1]));
  assert.ok(max < 0.06, `max step ${max}`);
});

test('Pitch +12 halbiert die Dauer, Transposition und Speed wirken', () => {
  let e = engineWith(dc(0.5, 2000), neutral({ pitch: 12 }));
  e.noteOn(0, 1); near(lastNonZero(render(e, 4000).L), 1000, 4);
  e = engineWith(dc(0.5, 2000));
  e.noteOnTransposed(0, 1, -12); near(lastNonZero(render(e, 6000).L), 4000, 6);
  e = engineWith(dc(0.5, 1000), neutral({ speed: 0.5 }));
  e.noteOn(0, 1); near(lastNonZero(render(e, 4000).L), 2000, 4);
});

test('Time-Stretch hält die Dauer bei Pitch +12', () => {
  const n = SR; const sine = new Float32Array(n).map((_, i) => Math.sin(2 * Math.PI * 220 * i / SR));
  const e = engineWith(makeSample([sine], SR), neutral({ pitchMode: 'timeStretch', pitch: 12 }));
  e.noteOn(0, 1);
  const { L } = render(e, 2 * n);
  near(lastNonZero(L) / SR, 1, 0.08);
});

test('Reverse, Loop und Gate', () => {
  const ramp = makeSample([Float32Array.from({ length: 4410 }, (_, i) => i / 4410)], SR);
  let e = engineWith(ramp, neutral({ reverse: true }));
  e.noteOn(0, 1); assert.ok(render(e, 200).L[100] > 0.9);
  e = engineWith(dc(0.5, 500), neutral({ playMode: 'loop', release: 0.02 }));
  e.noteOn(0, 1); near(render(e, 5000).L[4500], 0.5, 0.01);
  e.noteOff(0); near(render(e, 5000).L[4000], 0, 0.0001);
});

test('Polyphonie-Limit mit Voice-Stealing und "none"', () => {
  let e = engineWith(dc(0.1, SR));
  e.setEngineSettings({ polyphony: 4, stealMode: 'oldest' });
  for (let i = 0; i < 10; i++) e.noteOn(0, 1);
  const { L } = render(e, 2048);
  assert.ok(e.status.activeVoices <= 4);
  near(L[2000], 0.4, 0.02);
  e = new SamplerEngine(SR);
  e.setMaster({ ...defaultMaster(), volume: 1 });
  for (let p = 0; p < 3; p++) { e.setSample(p, dc(0.1, SR)); e.setPadSettings(p, neutral()); }
  e.setEngineSettings({ polyphony: 2, stealMode: 'none' });
  for (let p = 0; p < 3; p++) e.noteOn(p, 1);
  render(e, 512);
  assert.equal(e.status.padTriggers[2], 0);
});

test('Choke-Gruppe, Filter-EG und Insert-FX-Bypass', () => {
  const e = new SamplerEngine(SR);
  e.setMaster({ ...defaultMaster(), volume: 1 });
  for (const p of [4, 5]) { e.setSample(p, dc(0.3, SR)); e.setPadSettings(p, neutral({ chokeGroup: 1 })); }
  e.noteOn(4, 1); render(e, 1000); e.noteOn(5, 1);
  near(render(e, 1000).L[900], 0.3, 0.01);

  const sine = makeSample([new Float32Array(SR / 2).map((_, i) => Math.sin(2 * Math.PI * 5000 * i / SR))], SR);
  const rms = (x) => Math.sqrt(x.reduce((a, b) => a + b * b, 0) / x.length);
  let a = engineWith(sine, neutral({ filterMode: 'lowPass', cutoff: 100 }));
  a.noteOn(0, 1); const quiet = rms(render(a, 6000).L.subarray(1000));
  let b = engineWith(sine, neutral({ filterMode: 'lowPass', cutoff: 100, filterEnvAmount: 1 }));
  b.noteOn(0, 1); const loud = rms(render(b, 6000).L.subarray(1000));
  assert.ok(loud > quiet * 10, `${loud} vs ${quiet}`);
});

test('Master-Effekte verändern das Signal', () => {
  const run = (m) => {
    const e = engineWith(dc(0.5, 200), neutral({ reverbSend: 1, delaySend: 1 }));
    e.setMaster({ ...defaultMaster(), volume: 1, ...m });
    e.noteOn(0, 1);
    return render(e, 20000).L;
  };
  const dry = run({});
  assert.ok(dry.subarray(1000).every((x) => Math.abs(x) < 1e-6));
  assert.ok(run({ reverbMix: 1 }).subarray(1000).some((x) => Math.abs(x) > 0.001), 'Hall');
  assert.ok(Math.abs(run({ delayMix: 1, delaySync: 'off', delayTime: 0.1, delayFeedback: 0 })[4510]) > 0.2, 'Delay');
  near(run({ crushBits: 2 })[100], 0.5, 0.001);
});

test('Sequencer: sample-genaue Schritte, Swing, Mute', () => {
  const pat = newPattern('T');
  for (const s of [0, 4, 8, 12]) pat.steps[0][s] = { active: true, velocity: 1, offset: 0 };
  let e = engineWith(dc(0.5, 400));
  e.setTempo(120, 50); e.setPattern(0, patternSnapshot(pat)); e.selectPattern(0, true); e.transport('play');
  const found = onsets(render(e, 22050 * 8 - 100, 333).L);
  assert.equal(found.length, 8);
  found.forEach((o, k) => near(o, k * 22050, 1, `Schritt ${k * 4}`));

  const sw = newPattern('S');
  sw.steps[0][0] = { active: true, velocity: 1, offset: 0 }; sw.steps[0][1] = { active: true, velocity: 1, offset: 0 };
  e = engineWith(dc(0.5, 400));
  e.setTempo(120, 66.6667); e.setPattern(0, patternSnapshot(sw)); e.transport('play');
  near(onsets(render(e, 20000).L)[1], 5512.5 * 4 / 3, 2, 'Swing');

  e = engineWith(dc(0.5, 400));
  e.setPattern(0, patternSnapshot(pat)); e.setTrackStates(1, 0); e.transport('play');
  assert.equal(onsets(render(e, 44100).L).length, 0);
});

test('Sequencer: Pattern-Wechsel am Taktende und Live-Aufnahme', () => {
  const a = newPattern('A'); a.steps[0][0] = { active: true, velocity: 1, offset: 0 };
  const b = newPattern('B'); b.steps[1][0] = { active: true, velocity: 1, offset: 0 };
  const e = new SamplerEngine(SR);
  e.setMaster({ ...defaultMaster(), volume: 1 });
  e.setSample(0, dc(0.5, 400)); e.setPadSettings(0, neutral({ pan: -1 }));
  e.setSample(1, dc(0.5, 400)); e.setPadSettings(1, neutral({ pan: 1 }));
  e.setPattern(0, patternSnapshot(a)); e.setPattern(1, patternSnapshot(b)); e.transport('play');
  render(e, 30000);
  e.selectPattern(1, false);
  const rest = render(e, 88200 * 2 - 30000);
  assert.equal(onsets(rest.L).length, 0);
  near(onsets(rest.R)[0] + 30000, 88200, 1);

  const r = engineWith(dc(0.5, 400));
  r.setPattern(0, patternSnapshot(newPattern('E'))); r.setRecording(true); r.transport('play');
  render(r, Math.floor(5512.5 * 6)); r.noteOn(0, 0.9); render(r, 256);
  assert.equal(r.recordedHits.length, 1);
  near(r.recordedHits[0].positionInPattern, 6, 0.1);
  assert.deepEqual(placeHit(r.recordedHits[0].positionInPattern, 16, 'sixteenth'), { step: 6, offset: 0 });
});

test('Quantisierung', () => {
  assert.deepEqual(placeHit(3.6, 16, 'sixteenth'), { step: 4, offset: 0 });
  assert.deepEqual(placeHit(14.5, 16, 'quarter'), { step: 0, offset: 0 });
  near(placeHit(4.2, 16, 'off').offset, 0.2, 1e-9);
  const p = newPattern('Q'); p.steps[2][5] = { active: true, velocity: 0.7, offset: 0.3 };
  const q = quantizePattern(p, 'quarter');
  assert.ok(q.steps[2][4].active && !q.steps[2][5].active);
});

test('Parameter-Registry: Normierung und Wirkungsbereiche', () => {
  for (const id of Object.keys(PARAMS)) {
    for (const n of [0, 0.3, 1]) {
      const v = fromNormalized(id, n);
      if (PARAMS[id].integer) assert.equal(fromNormalized(id, toNormalized(id, v)), v);
      else near(toNormalized(id, v), n, 1e-9, id);
    }
    assert.ok(formatValue(id, PARAMS[id].def).length > 0);
  }
  const p = newProject();
  assert.deepEqual(setValue(p, 'padPitch', 99, 3), { pad: 3 });
  assert.equal(getValue(p, 'padPitch', 3), 24);
  assert.equal(setValue(p, 'reverbMix', 0.3, 0), 'master');
  assert.equal(setValue(p, 'tempo', 133, 0), 'tempo');
  assert.equal(formatValue('masterFilterCutoff', 2400), '2.40k');
});

test('Projektformat: Mac-kompatibler Import mit fehlenden Feldern', () => {
  const p = normalizeProject({ formatVersion: 1, name: 'Old', bpm: 130, pads: [{ index: 2, name: 'X', settings: { volume: 0.5, futureKey: 1 } }] });
  assert.equal(p.pads.length, 16);
  assert.equal(p.pads[2].settings.volume, 0.5);
  assert.equal(p.pads[2].settings.pitch, 0);
  assert.equal(p.sequencer.patterns.length, 8);
  assert.throws(() => normalizeProject({ formatVersion: 99 }));
  const round = normalizeProject(JSON.parse(JSON.stringify(p)));
  assert.deepEqual(round.pads, p.pads);
});

test('WAV/AIFF: Kodieren und Dekodieren', () => {
  const left = Float32Array.from({ length: 300 }, (_, i) => Math.sin(i / 10) * 0.7);
  const right = left.map((x) => -x * 0.5);
  for (const [fmt, depth, tol] of [['wav', 'pcm16', 1 / 16000], ['wav', 'pcm24', 1 / 4e6], ['wav', 'float32', 0], ['aiff', 'pcm24', 1 / 4e6], ['aiff', 'pcm16', 1 / 16000]]) {
    const d = decodeAudio(encodeAudio(left, right, 48000, fmt, depth, { dither: false }));
    near(d.sampleRate, 48000, 1e-6, fmt);
    assert.equal(d.channels.length, 2);
    for (let i = 0; i < 300; i += 37) { near(d.channels[0][i], left[i], tol + 1e-7, `${fmt}/${depth}`); near(d.channels[1][i], right[i], tol + 1e-7); }
  }
  assert.throws(() => encodeAudio(left, right, 44100, 'aiff', 'float32'));
  const mono = decodeAudio(encodeAudio(left, left, 44100, 'wav', 'pcm16', { mono: true }));
  assert.equal(mono.channels.length, 1);
});

test('Offline-Export: Positionen und 48 kHz', () => {
  const proj = newProject('Export');
  proj.sequencer.patterns[0].steps[0][0] = { active: true, velocity: 1, offset: 0 };
  proj.sequencer.patterns[0].steps[0][8] = { active: true, velocity: 1, offset: 0 };
  proj.pads[0].settings = neutral();
  proj.master.volume = 1;
  const samples = Array(16).fill(null); samples[0] = dc(0.5, 441);
  const r = renderOffline({ sampleRate: 44100, project: proj, samples, patternOrder: [0], loops: 2, tailSeconds: 1 });
  const found = onsets(r.left);
  assert.equal(found.length, 4);
  found.forEach((o, k) => near(o, k * 44100, 1));
  const r48 = renderOffline({ sampleRate: 48000, project: proj, samples, patternOrder: [0], loops: 1, tailSeconds: 0 });
  near(onsets(r48.left)[1], 48000, 1);
});
