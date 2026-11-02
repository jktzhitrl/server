// Aufnahme neuer Samples (Portierung von NexoraCore/Sampling/SampleRecorder.swift).
// Wird mit Blöcken aus dem Aufnahme-Worklet gefüttert (Mikrofon, Line-In oder Resampling).

import { makeSample } from './engine.js';

const dbToGain = (db) => Math.pow(10, db / 20);

export class SampleRecorder {
  /** @param {{ thresholdDb?: number|null, maxSeconds?: number, preRollSeconds?: number, trimTrailingSilence?: boolean }} o */
  constructor(sampleRate, o = {}) {
    this.sampleRate = sampleRate;
    this.thresholdDb = o.thresholdDb ?? null;
    this.maxFrames = Math.max(1, Math.floor((o.maxSeconds ?? 600) * sampleRate));
    this.preRollFrames = Math.max(0, Math.floor((o.preRollSeconds ?? 0.01) * sampleRate));
    this.trim = o.trimTrailingSilence ?? true;
    this.threshold = this.thresholdDb == null ? 0 : dbToGain(this.thresholdDb);
    this.state = this.thresholdDb == null ? 'recording' : 'armed';
    this.level = 0;
    this.stereo = false;
    this.chunksL = []; this.chunksR = []; this.frames = 0;
    this.preL = new Float32Array(0); this.preR = new Float32Array(0);
  }

  get recordedSeconds() { return this.frames / this.sampleRate; }

  /** Hängt einen Block an (`right` = null bei Mono). */
  append(left, right) {
    const n = left.length;
    if (!n) return;
    let peak = 0;
    for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(left[i]), right ? Math.abs(right[i]) : 0);
    this.level = peak;
    if (right) this.stereo = true;
    const R = right ?? left;
    if (this.state === 'finished') return;
    if (this.state === 'armed') {
      let first = -1;
      for (let i = 0; i < n; i++) if (Math.max(Math.abs(left[i]), Math.abs(R[i])) >= this.threshold) { first = i; break; }
      if (first < 0) {
        this.preL = tail(concat(this.preL, left), this.preRollFrames);
        this.preR = tail(concat(this.preR, R), this.preRollFrames);
        return;
      }
      const lead = Math.min(first, this.preRollFrames);
      const fromPre = Math.max(0, this.preRollFrames - lead);
      this._push(tail(this.preL, fromPre), tail(this.preR, fromPre));
      this.preL = new Float32Array(0); this.preR = new Float32Array(0);
      this.state = 'recording';
      this._push(left.subarray(first - lead), R.subarray(first - lead));
      return;
    }
    this._push(left, R);
  }

  _push(l, r) {
    const n = Math.min(l.length, this.maxFrames - this.frames);
    if (n <= 0) { this.state = 'finished'; return; }
    this.chunksL.push(Float32Array.from(l.subarray(0, n)));
    this.chunksR.push(Float32Array.from(r.subarray(0, n)));
    this.frames += n;
    if (this.frames >= this.maxFrames) this.state = 'finished';
  }

  /** Beendet die Aufnahme; null, wenn nichts (Hörbares) aufgenommen wurde. */
  finish(name) {
    this.state = 'finished';
    let L = join(this.chunksL, this.frames), R = join(this.chunksR, this.frames);
    if (this.trim) {
      const floor = dbToGain(-60);
      let end = L.length;
      while (end > 0 && Math.abs(L[end - 1]) < floor && Math.abs(R[end - 1]) < floor) end--;
      if (end === 0) return null;
      const keep = Math.min(L.length, end + Math.floor(0.02 * this.sampleRate));
      L = L.slice(0, keep); R = R.slice(0, keep);
    }
    if (L.length <= Math.floor(0.005 * this.sampleRate)) return null;
    let differs = false;
    if (this.stereo) for (let i = 0; i < L.length; i++) if (L[i] !== R[i]) { differs = true; break; }
    return makeSample(differs ? [L, R] : [L], this.sampleRate, name);
  }
}

function concat(a, b) { const out = new Float32Array(a.length + b.length); out.set(a); out.set(b, a.length); return out; }
function tail(a, n) { return n <= 0 ? new Float32Array(0) : a.length > n ? a.slice(a.length - n) : a.slice(); }
function join(chunks, total) {
  const out = new Float32Array(total);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}
