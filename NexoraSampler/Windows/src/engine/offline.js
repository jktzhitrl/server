// Offline-Export mit derselben Engine wie die Live-Wiedergabe (Portierung von OfflineRenderer.swift).

import { SamplerEngine, patternSnapshot } from './engine.js';
import { muteMask, PATTERN_SLOTS } from './model.js';

/**
 * @param {object} req { sampleRate, project, samples: (sample|null)[16], patternOrder: number[], loops, tailSeconds }
 * @param {(p:number)=>boolean} [progress] false = Abbruch
 */
export function renderOffline(req, progress) {
  const doc = req.project;
  const e = new SamplerEngine(req.sampleRate);
  for (let p = 0; p < 16; p++) { e.setPadSettings(p, doc.pads[p].settings); e.setSample(p, req.samples[p] ?? null); }
  e.setMaster(doc.master);
  e.setEngineSettings(doc.engine);
  e.setTempo(doc.bpm, doc.swing);
  e.setTrackStates(muteMask(doc.sequencer.trackMutes), muteMask(doc.sequencer.trackSolos));
  e.setMetronome(false);
  doc.sequencer.patterns.forEach((pat, slot) => e.setPattern(slot, patternSnapshot(pat)));
  let order = [];
  for (const slot of req.patternOrder ?? []) if (slot >= 0 && slot < PATTERN_SLOTS) for (let i = 0; i < Math.max(1, req.loops); i++) order.push(slot);
  if (!order.length) order = Array(Math.max(1, req.loops)).fill(doc.sequencer.currentPattern);
  const totalSteps = order.reduce((a, s) => a + doc.sequencer.patterns[s].length, 0);
  const stepFrames = (req.sampleRate * 60) / doc.bpm / 4;
  const playFrames = Math.ceil(totalSteps * stepFrames);
  const maxTail = Math.floor((req.tailSeconds ?? 3) * req.sampleRate);
  const block = 512;
  e.selectPattern(order[0], true);
  e.transport('play');
  const L = new Float32Array(playFrames + maxTail), R = new Float32Array(playFrames + maxTail);
  const bl = new Float32Array(block), br = new Float32Array(block);
  const bounds = [];
  let acc = 0;
  for (const s of order) { acc += doc.sequencer.patterns[s].length; bounds.push(acc); }
  let idx = 0, queued = false, rendered = 0;
  const total = playFrames + maxTail / 2;
  while (rendered < playFrames) {
    const n = Math.min(block, playFrames - rendered);
    if (!queued && idx + 1 < order.length) {
      const start = idx === 0 ? 0 : bounds[idx - 1];
      if (e.sequencerPosition >= start + 0.01) { e.selectPattern(order[idx + 1], false); queued = true; }
    }
    e.render(n, bl, br);
    L.set(bl.subarray(0, n), rendered); R.set(br.subarray(0, n), rendered);
    rendered += n;
    if (queued && e.sequencerPosition >= bounds[idx]) { idx++; queued = false; }
    if (progress && progress(rendered / total) === false) throw new Error('cancelled');
  }
  e.transport('stop');
  let silent = 0, tail = 0;
  const needSilence = Math.floor(0.2 * req.sampleRate);
  while (tail < maxTail) {
    const n = Math.min(block, maxTail - tail);
    e.render(n, bl, br);
    L.set(bl.subarray(0, n), rendered + tail); R.set(br.subarray(0, n), rendered + tail);
    tail += n;
    let pk = 0;
    for (let i = 0; i < n; i++) pk = Math.max(pk, Math.abs(bl[i]), Math.abs(br[i]));
    silent = pk < 0.00003 ? silent + n : 0;
    if (silent >= needSilence) break;
  }
  let length = rendered + tail;
  if (silent > 0) length = Math.max(Math.min(length, length - silent + Math.floor(0.05 * req.sampleRate)), playFrames);
  return { left: L.slice(0, length), right: R.slice(0, length), sampleRate: req.sampleRate };
}

export function normalizeResult(r) {
  let pk = 0;
  for (let i = 0; i < r.left.length; i++) pk = Math.max(pk, Math.abs(r.left[i]), Math.abs(r.right[i]));
  if (pk < 0.0001) return r;
  const g = Math.pow(10, -0.3 / 20) / pk;
  for (let i = 0; i < r.left.length; i++) { r.left[i] *= g; r.right[i] *= g; }
  return r;
}
