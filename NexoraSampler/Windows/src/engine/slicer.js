// Zerlegt ein Sample in Slices (Portierung von NexoraCore/Sampling/SampleSlicer.swift).
// Eine Slice ist ein Bereich { start, end } (0 … 1) innerhalb desselben Samples.

import { clamp } from './dsp.js';

export const MAX_SLICES = 16;

/**
 * @param {Float32Array} left
 * @param {Float32Array|null} right  null bei Mono
 * @param {{ type: 'equal', count: number } | { type: 'transients', sensitivity: number, maxSlices: number }} mode
 */
export function slices(left, right, sampleRate, mode, regionStart = 0, regionEnd = 1) {
  const a = clamp(Math.min(regionStart, regionEnd), 0, 1);
  const b = clamp(Math.max(regionStart, regionEnd), 0, 1);
  if (b - a <= 1e-6 || !left.length) return [{ start: 0, end: 1 }];
  let starts;
  if (mode.type === 'equal') {
    const n = clamp(mode.count | 0, 1, MAX_SLICES);
    starts = Array.from({ length: n }, (_, i) => a + ((b - a) * i) / n);
  } else {
    const frames = left.length;
    const from = Math.floor(a * frames), to = Math.floor(b * frames);
    const on = detectOnsets(left, right, from, to, sampleRate, mode.sensitivity, clamp(mode.maxSlices | 0, 1, MAX_SLICES));
    starts = [a, ...on.map((f) => f / frames).filter((x) => x > a + 1e-6 && x < b - 1e-6)];
  }
  starts.sort((x, y) => x - y);
  const out = [];
  starts.forEach((s, i) => {
    const e = i + 1 < starts.length ? starts[i + 1] : b;
    if (e - s > 1e-6) out.push({ start: s, end: e });
  });
  return out;
}

/** Anschlagerkennung über den Anstieg der Kurzzeit-Energie; Frame-Positionen ohne Bereichsanfang. */
export function detectOnsets(left, right, from, to, sampleRate, sensitivity, maxCount) {
  const hop = 256;
  const count = Math.floor((to - from) / hop);
  if (count <= 4) return [];
  const mono = (i) => (right ? (left[i] + right[i]) * 0.5 : left[i]);
  const env = new Float32Array(count);
  for (let h = 0; h < count; h++) {
    let sum = 0;
    const base = from + h * hop;
    for (let i = base; i < Math.min(base + hop, to); i++) { const v = mono(i); sum += v * v; }
    env[h] = Math.sqrt(sum / hop);
  }
  let maxEnv = 0;
  for (const v of env) if (v > maxEnv) maxEnv = v;
  if (maxEnv <= 1e-5) return [];
  const s = clamp(sensitivity, 0, 1);
  const floor = maxEnv * (0.12 - 0.1 * s);
  const ratio = 1.6 + (1 - s) * 4.4;
  const minGap = Math.max(1, Math.floor(Math.floor(0.05 * sampleRate) / hop));
  const preRoll = Math.floor(0.002 * sampleRate);
  let candidates = [];
  let last = 0;
  for (let h = 1; h < count; h++) {
    const lo = Math.max(0, h - 4);
    let avg = 0;
    for (let j = lo; j < h; j++) avg += env[j];
    avg /= h - lo;
    const strength = env[h] / Math.max(avg, floor * 0.5);
    if (!(env[h] > floor && strength > ratio && h - last >= minGap)) continue;
    const base = from + h * hop;
    let onset = base;
    const level = Math.max(avg, 1e-6) * 1.5;
    for (let i = Math.max(from, base - hop); i < Math.min(base + hop, to); i++) {
      if (Math.abs(mono(i)) > level) { onset = i; break; }
    }
    candidates.push({ frame: Math.max(from, onset - preRoll), strength });
    last = h;
  }
  if (candidates.length > maxCount - 1) {
    candidates = candidates.sort((x, y) => y.strength - x.strength).slice(0, Math.max(0, maxCount - 1));
  }
  return candidates.map((c) => c.frame).sort((x, y) => x - y);
}

/** Schritte, auf die die Slices fallen, wenn das Sample genau einem Pattern-Durchlauf entspricht. */
export function patternSteps(sl, length) {
  if (!sl.length) return [];
  const first = sl[0].start, span = Math.max(sl[sl.length - 1].end - first, 1e-9);
  const used = new Set();
  return sl.map((x) => {
    let step = clamp(Math.round(((x.start - first) / span) * length), 0, Math.max(0, length - 1));
    while (used.has(step) && step < length - 1) step++;
    used.add(step);
    return step;
  });
}
