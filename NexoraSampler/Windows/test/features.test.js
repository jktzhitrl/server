// Tests für 64-Schritt-Patterns, Song-Modus, Motion-Sequenz, Slice, Aufnahme und Resampling
// (gleiche Szenarien wie GrooveboxFeatureTests/SamplingTests im Swift-Kern).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SamplerEngine, makeSample, patternSnapshot } from '../src/engine/engine.js';
import { defaultPadSettings, defaultMaster, newPattern, newProject, normalizeProject, normalizePattern, compactPattern,
  recordMotion, fillMotion, canRecordMotion, PARAMS, MAX_STEPS, MOTION_MAX_LANES, newStep } from '../src/engine/model.js';
import { slices, patternSteps } from '../src/engine/slicer.js';
import { SampleRecorder } from '../src/engine/recorder.js';
import { renderOffline } from '../src/engine/offline.js';

const SR = 44100, STEP = 5512.5;
const dc = (v, n) => makeSample([new Float32Array(n).fill(v)], SR);
const neutral = () => ({ ...defaultPadSettings(), volume: 1, velocitySensitivity: 0, reverbSend: 0, delaySend: 0 });
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg ?? ''} ${a} ≉ ${b} ± ${tol}`);
function engine(patterns, frames = 400) {
  const e = new SamplerEngine(SR);
  e.setMaster({ ...defaultMaster(), volume: 1 });
  for (const pad of [0, 1]) { e.setSample(pad, dc(0.5, frames)); e.setPadSettings(pad, neutral()); }
  e.setTempo(120, 50);
  patterns.forEach((p, i) => e.setPattern(i, patternSnapshot(p)));
  e.selectPattern(0, true);
  return e;
}
function render(e, frames, block = 256) {
  const L = new Float32Array(frames), bl = new Float32Array(block), br = new Float32Array(block);
  for (let d = 0; d < frames; d += block) { const n = Math.min(block, frames - d); e.render(n, bl, br); L.set(bl.subarray(0, n), d); }
  return L;
}
function onsets(x, gap = 200) {
  const out = []; let silent = gap;
  for (let i = 0; i < x.length; i++) { if (Math.abs(x[i]) > 0.001) { if (silent >= gap) out.push(i); silent = 0; } else silent++; }
  return out;
}
const rms = (x, a, b) => { let s = 0; for (let i = a; i < b; i++) s += x[i] * x[i]; return Math.sqrt(s / (b - a)); };
const level = (x, step) => rms(x, Math.floor(step * STEP) - 300, Math.floor(step * STEP) + 300);
const on = (p, t, s, v = 1) => { p.steps[t][s] = newStep(true, v, 0); };

test('64-Schritt-Pattern spielt alle vier Takte', () => {
  const p = newPattern('L', 64);
  for (const s of [0, 20, 48, 63]) on(p, 0, s);
  const e = engine([p]); e.transport('play');
  const found = onsets(render(e, Math.floor(STEP * 66)));
  assert.equal(found.length, 5);
  [0, 20, 48, 63, 64].forEach((s, i) => near(found[i], Math.ceil(s * STEP), 1, `Schritt ${s}`));
  assert.equal(newPattern('X', 200).length, 64);
});

test('Speichern schreibt nur belegte Seiten, alte 16-Schritt-Dateien laden', () => {
  const p = newPattern('P', 16);
  on(p, 3, 2, 0.5);
  assert.equal(compactPattern(p).steps[0].length, 16);
  on(p, 3, 40, 0.7);
  const c = compactPattern(p);
  assert.equal(c.steps[0].length, 48);
  const back = normalizePattern(JSON.parse(JSON.stringify(c)));
  assert.equal(back.steps[3].length, MAX_STEPS);
  assert.ok(back.steps[3][40].active);
  const old = normalizePattern({ name: 'Alt', length: 16, steps: Array.from({ length: 16 }, () => Array(16).fill({ active: false })) });
  assert.ok(old.steps.every((t) => t.length === 64));
  assert.deepEqual(old.motion, []);
});

test('Song-Modus folgt der Kette und beginnt am Ende von vorn', () => {
  const a = newPattern('A', 4); on(a, 0, 0);
  const b = newPattern('B', 4); on(b, 1, 2);
  const e = engine([a, b]);
  e.setSong([0, 1, 1]); e.transport('play');
  const found = onsets(render(e, Math.floor(STEP * 17)));
  const expected = [0, 6, 10, 12];
  assert.equal(found.length, expected.length);
  expected.forEach((s, i) => near(found[i], Math.ceil(s * STEP), 1, `Schritt ${s}`));
});

test('Song-Status und hörbares Pattern wechseln nicht zu früh', () => {
  const e = engine([newPattern('A', 4), newPattern('B', 2)]);
  e.setSong([1, 0]); e.transport('play');
  render(e, Math.floor(STEP));
  assert.equal(e.status.currentPattern, 1); assert.equal(e.status.songIndex, 0);
  render(e, Math.floor(STEP * 2.5));
  assert.equal(e.status.currentPattern, 0); assert.equal(e.status.songIndex, 1);
  e.setSong(null); render(e, 64);
  assert.equal(e.status.songIndex, -1);

  const f = engine([newPattern('A', 4), newPattern('B', 4)]);
  f.transport('play'); render(f, Math.floor(STEP));
  f.selectPattern(1, false); render(f, Math.floor(STEP * 2.5));
  assert.equal(f.status.currentPattern, 0); assert.equal(f.status.currentStep, 3);
  render(f, Math.floor(STEP));
  assert.equal(f.status.currentPattern, 1); assert.equal(f.status.currentStep, 0);
});

test('Motion (Stufen) ändert den Parameter je Schritt', () => {
  const p = newPattern('M', 4); on(p, 0, 0);
  recordMotion(p, 'padVolume', 0, 0, 1.0);
  recordMotion(p, 'padVolume', 0, 2, 0.25);
  const e = engine([p], Math.floor(STEP * 5)); e.transport('play');
  const out = render(e, Math.floor(STEP * 4));
  const l1 = level(out, 1.5), l3 = level(out, 3.5);
  near(l1, 0.5, 0.02); near(l3 / l1, 0.25, 0.02);
});

test('Motion (glatt) blendet über', () => {
  const p = newPattern('M', 4); on(p, 0, 0);
  recordMotion(p, 'padVolume', 0, 0, 1.0);
  recordMotion(p, 'padVolume', 0, 2, 0.0);
  const e = engine([p], Math.floor(STEP * 5)); e.setMotionMode('smooth'); e.transport('play');
  const out = render(e, Math.floor(STEP * 4));
  near(level(out, 1.0) / 0.5, 0.5, 0.05);
});

test('Nach Stopp gilt wieder der Grundwert; Master-Motion wirkt', () => {
  const p = newPattern('M', 4);
  recordMotion(p, 'padVolume', 0, 0, 0.1);
  const e = engine([p], 20000); e.transport('play'); render(e, 2000); e.transport('stop');
  e.noteOn(0, 1);
  near(rms(render(e, 3000), 1000, 2500), 0.5, 0.02);

  const q = newPattern('Q', 4); on(q, 0, 0);
  recordMotion(q, 'masterVolume', 0, 2, 0.5); recordMotion(q, 'masterVolume', 0, 0, 1.0);
  const f = engine([q], Math.floor(STEP * 5)); f.transport('play');
  const out = render(f, Math.floor(STEP * 4));
  const ratio = level(out, 3.5) / level(out, 1.5);
  assert.ok(ratio < 0.6 && ratio > 0.1, String(ratio));
});

test('Motion-Aufnahme füllt Lücken, begrenzt Spuren, Fill ist zyklisch', () => {
  const p = newPattern('M');
  recordMotion(p, 'padCutoff', 3, 2, 1000);
  recordMotion(p, 'padCutoff', 3, 6, 5000, 2, 1000);
  assert.equal(p.motion[0].pad, 3);
  near(p.motion[0].values[4], 3000, 1e-6);
  assert.equal(p.motion[0].values[1], null);
  assert.equal(recordMotion(p, 'tempo', 0, 0, 100), false);
  const ids = Object.keys(PARAMS).filter(canRecordMotion);
  for (let i = 0; i < 40; i++) recordMotion(p, ids[i % ids.length], Math.floor(i / ids.length), 0, PARAMS[ids[i % ids.length]].def);
  assert.equal(p.motion.length, MOTION_MAX_LANES);
  const { hold, smooth } = fillMotion([null, 2, null, 6]);
  assert.deepEqual(hold, [6, 2, 2, 6]); near(smooth[2], 4, 1e-9); near(smooth[0], 4, 1e-9);
});

test('Motion, Song-Modus und Kette überstehen Speichern/Laden', () => {
  const doc = newProject('M');
  recordMotion(doc.sequencer.patterns[0], 'reverbMix', 0, 5, 0.7);
  doc.sequencer.motionMode = 'smooth'; doc.sequencer.songMode = true; doc.patternChain = [0, 1, 1, 0];
  const back = normalizeProject(JSON.parse(JSON.stringify(doc)));
  assert.equal(back.sequencer.patterns[0].motion[0].values[5], 0.7);
  assert.equal(back.sequencer.patterns[0].motion[0].pad, -1);
  assert.equal(back.sequencer.motionMode, 'smooth');
  assert.equal(back.sequencer.songMode, true);
  assert.deepEqual(back.patternChain, [0, 1, 1, 0]);
});

// ---------------------------------------------------------------- Slice

function drumLoop(hits, frames, amps) {
  const x = new Float32Array(frames);
  hits.forEach((h, k) => { const a = amps?.[k] ?? 0.8; for (let i = 0; i < Math.min(8000, frames - h); i++) x[h + i] += a * Math.exp(-i / 1500) * Math.sin(i * 0.3); });
  return x;
}

test('Slice: gleichmäßig und nach Transienten', () => {
  const eq = slices(new Float32Array(1000).fill(0.1), null, SR, { type: 'equal', count: 4 }, 0.2, 0.6);
  assert.equal(eq.length, 4); near(eq[1].start, 0.3, 1e-9); near(eq[3].end, 0.6, 1e-9);
  const hits = [0, 11025, 22050, 33075];
  const t = slices(drumLoop(hits, 44100), null, SR, { type: 'transients', sensitivity: 0.5, maxSlices: 16 });
  assert.equal(t.length, 4);
  t.forEach((s, i) => near(s.start * 44100, hits[i], 300, `Slice ${i}`));
  const quiet = drumLoop(hits, 44100, [0.9, 0.9, 0.06, 0.9]);
  assert.equal(slices(quiet, null, SR, { type: 'transients', sensitivity: 0, maxSlices: 16 }).length, 3);
  assert.equal(slices(quiet, null, SR, { type: 'transients', sensitivity: 1, maxSlices: 16 }).length, 4);
  const many = slices(drumLoop(Array.from({ length: 10 }, (_, i) => i * 4000), 44100), null, SR, { type: 'transients', sensitivity: 0.6, maxSlices: 4 });
  assert.equal(many.length, 4); near(many[3].end, 1, 1e-9);
  assert.deepEqual(slices(new Float32Array(10000), null, SR, { type: 'transients', sensitivity: 1, maxSlices: 16 }), [{ start: 0, end: 1 }]);
  assert.deepEqual(patternSteps([{ start: 0, end: 0.25 }, { start: 0.25, end: 0.5 }, { start: 0.5, end: 0.75 }, { start: 0.75, end: 1 }], 16), [0, 4, 8, 12]);
});

// ---------------------------------------------------------------- Aufnahme & Resampling

const sine = (sec) => Float32Array.from({ length: Math.floor(sec * SR) }, (_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / SR));
function feed(r, x, block = 512) { for (let i = 0; i < x.length; i += block) r.append(x.subarray(i, Math.min(x.length, i + block)), null); }

test('Rekorder: sofort, mit Schwelle und Vorlauf, Maximallänge, Stille', () => {
  const a = new SampleRecorder(SR, { trimTrailingSilence: false });
  assert.equal(a.state, 'recording'); feed(a, sine(0.5));
  assert.equal(a.finish('R').frameCount, 22050);

  const b = new SampleRecorder(SR, { thresholdDb: -30, preRollSeconds: 0.01 });
  const x = new Float32Array(30000).fill(0.0001); x.fill(0.5, 20000);
  feed(b, x, 700); assert.equal(b.state, 'recording');
  near(b.finish('R').frameCount, 10000 + 441, 2);

  const c = new SampleRecorder(SR, { maxSeconds: 0.1, trimTrailingSilence: false });
  feed(c, sine(1)); assert.equal(c.state, 'finished'); assert.equal(c.finish('R').frameCount, 4410);

  const d = new SampleRecorder(SR);
  const y = new Float32Array(8820 + 20000); y.set(sine(0.2));
  feed(d, y); assert.ok(d.finish('R').frameCount < 8820 + 1000);
  const empty = new SampleRecorder(SR); feed(empty, new Float32Array(5000));
  assert.equal(empty.finish('E'), null);
});

test('Resampling rendert genau einen Pattern-Durchlauf', () => {
  const doc = newProject('R');
  doc.master.volume = 1; doc.pads[0].settings = neutral();
  doc.sequencer.patterns[0].length = 8;
  on(doc.sequencer.patterns[0], 0, 0); on(doc.sequencer.patterns[0], 0, 4);
  const samples = Array(16).fill(null); samples[0] = dc(0.5, 500);
  const r = renderOffline({ sampleRate: SR, project: doc, samples, patternOrder: [0], loops: 1, tailSeconds: 0 });
  near(r.left.length, 8 * STEP, 2);
  assert.equal(onsets(r.left).length, 2);
});
