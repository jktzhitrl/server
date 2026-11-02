// NEXORA Sampler – DSP-Bausteine (Portierung von NexoraCore/DSP, gleiche Algorithmen).
// Alle Klassen sind allokationsfrei im Betrieb und für den Audio-Thread (AudioWorklet) geeignet.

export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
export const dbToGain = (db) => Math.pow(10, db / 20);
export const gainToDb = (g) => (g <= 1e-9 ? -180 : 20 * Math.log10(g));
export const semitonesToRatio = (s) => Math.pow(2, s / 12);
export const flushDenormal = (x) => (Math.abs(x) < 1e-20 ? 0 : x);
export const onePoleCoefficient = (time, sr) => (time > 0 && sr > 0 ? Math.exp(-1 / (time * sr)) : 0);

/** Balance-Panning mit Einheitsverstärkung in der Mitte. Schreibt in out[0], out[1]. */
export function balanceGains(pan, out) {
  const p = clamp(pan, -1, 1);
  out[0] = Math.min(1, 1 - p);
  out[1] = Math.min(1, 1 + p);
  return out;
}

export function fastTanh(x) {
  if (x > 3) return 1;
  if (x < -3) return -1;
  const x2 = x * x;
  return (x * (27 + x2)) / (27 + 9 * x2);
}

export function hermite(xm1, x0, x1, x2, t) {
  const c1 = 0.5 * (x1 - xm1);
  const c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2;
  const c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1);
  return ((c3 * t + c2) * t + c1) * t + x0;
}

export class SmoothedValue {
  constructor(value, time = 0.01, sr = 44100) {
    this.current = value;
    this.target = value;
    this.coeff = onePoleCoefficient(time, sr);
  }
  reset(v) { this.current = v; this.target = v; }
  next() {
    this.current = this.target + this.coeff * (this.current - this.target);
    if (Math.abs(this.current - this.target) < 1e-6) this.current = this.target;
    return this.current;
  }
}

export class FastRandom {
  constructor(seed = 0x12345678) { this.state = (seed >>> 0) || 0x12345678; }
  nextUInt32() {
    let s = this.state;
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    this.state = s;
    return s;
  }
  nextBipolar() { return (this.nextUInt32() / 4294967295) * 2 - 1; }
}

export const FilterMode = { off: 'off', lowPass: 'lowPass', highPass: 'highPass', bandPass: 'bandPass' };

/** TPT-Zustandsvariablenfilter (Zavalishin/Simper), stereo, 12 dB/Okt. */
export class StateVariableFilter {
  constructor() {
    this.ic1L = 0; this.ic2L = 0; this.ic1R = 0; this.ic2R = 0;
    this.k = 2; this.a1 = 0; this.a2 = 0; this.a3 = 0;
    this.mode = 'lowPass';
    this.outL = 0; this.outR = 0;
    this.setParameters(1000, 0, 44100);
  }
  setParameters(cutoff, resonance, sr) {
    const fc = clamp(cutoff, 10, sr * 0.49);
    const g = Math.tan((Math.PI * fc) / sr);
    this.k = 2 - 1.96 * clamp(resonance, 0, 1);
    this.a1 = 1 / (1 + g * (g + this.k));
    this.a2 = g * this.a1;
    this.a3 = g * this.a2;
  }
  reset() { this.ic1L = this.ic2L = this.ic1R = this.ic2R = 0; }
  _out(x, v1, v2) {
    switch (this.mode) {
      case 'lowPass': return v2;
      case 'highPass': return x - this.k * v1 - v2;
      case 'bandPass': return this.k * v1;
      default: return x;
    }
  }
  /** Verarbeitet ein Stereo-Sample; Ergebnis in this.outL / this.outR. */
  process(l, r) {
    if (this.mode === 'off') { this.outL = l; this.outR = r; return; }
    const v3L = l - this.ic2L;
    const v1L = this.a1 * this.ic1L + this.a2 * v3L;
    const v2L = this.ic2L + this.a2 * this.ic1L + this.a3 * v3L;
    this.ic1L = flushDenormal(2 * v1L - this.ic1L);
    this.ic2L = flushDenormal(2 * v2L - this.ic2L);
    const v3R = r - this.ic2R;
    const v1R = this.a1 * this.ic1R + this.a2 * v3R;
    const v2R = this.ic2R + this.a2 * this.ic1R + this.a3 * v3R;
    this.ic1R = flushDenormal(2 * v1R - this.ic1R);
    this.ic2R = flushDenormal(2 * v2R - this.ic2R);
    this.outL = this._out(l, v1L, v2L);
    this.outR = this._out(r, v1R, v2R);
  }
  processMono(x) {
    if (this.mode === 'off') return x;
    const v3 = x - this.ic2L;
    const v1 = this.a1 * this.ic1L + this.a2 * v3;
    const v2 = this.ic2L + this.a2 * this.ic1L + this.a3 * v3;
    this.ic1L = flushDenormal(2 * v1 - this.ic1L);
    this.ic2L = flushDenormal(2 * v2 - this.ic2L);
    return this._out(x, v1, v2);
  }
}

/** RBJ-Biquad (Audio EQ Cookbook), transponierte Direktform II, stereo. */
export class Biquad {
  constructor() {
    this.b0 = 1; this.b1 = 0; this.b2 = 0; this.a1 = 0; this.a2 = 0;
    this.z1L = 0; this.z2L = 0; this.z1R = 0; this.z2R = 0;
    this.isIdentity = true;
    this.outL = 0; this.outR = 0;
  }
  configure(kind, frequency, q, gainDb, sr) {
    const f = Math.min(Math.max(frequency, 10), sr * 0.49);
    const w0 = (2 * Math.PI * f) / sr;
    const cosw = Math.cos(w0), sinw = Math.sin(w0);
    const A = Math.pow(10, gainDb / 40);
    const alpha = sinw / (2 * Math.max(q, 0.05));
    let b0 = 1, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;
    if (kind === 'peaking') {
      b0 = 1 + alpha * A; b1 = -2 * cosw; b2 = 1 - alpha * A;
      a0 = 1 + alpha / A; a1 = -2 * cosw; a2 = 1 - alpha / A;
    } else if (kind === 'lowShelf') {
      const s = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cosw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cosw); b2 = A * ((A + 1) - (A - 1) * cosw - s);
      a0 = (A + 1) + (A - 1) * cosw + s; a1 = -2 * ((A - 1) + (A + 1) * cosw); a2 = (A + 1) + (A - 1) * cosw - s;
    } else if (kind === 'highShelf') {
      const s = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cosw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cosw); b2 = A * ((A + 1) + (A - 1) * cosw - s);
      a0 = (A + 1) - (A - 1) * cosw + s; a1 = 2 * ((A - 1) - (A + 1) * cosw); a2 = (A + 1) - (A - 1) * cosw - s;
    }
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = a1 / a0; this.a2 = a2 / a0;
    this.isIdentity = Math.abs(gainDb) < 0.01;
  }
  reset() { this.z1L = this.z2L = this.z1R = this.z2R = 0; }
  process(l, r) {
    const yL = this.b0 * l + this.z1L;
    this.z1L = flushDenormal(this.b1 * l - this.a1 * yL + this.z2L);
    this.z2L = flushDenormal(this.b2 * l - this.a2 * yL);
    const yR = this.b0 * r + this.z1R;
    this.z1R = flushDenormal(this.b1 * r - this.a1 * yR + this.z2R);
    this.z2R = flushDenormal(this.b2 * r - this.a2 * yR);
    this.outL = yL; this.outR = yR;
  }
}

export class ThreeBandEQ {
  constructor(sr) {
    this.sr = sr;
    this.low = new Biquad(); this.mid = new Biquad(); this.high = new Biquad();
    this.last = [NaN, NaN, NaN, NaN];
    this.outL = 0; this.outR = 0;
    this.configure(0, 0, 0, 1000);
  }
  configure(lowDb, midDb, highDb, midFreq) {
    if (lowDb !== this.last[0]) { this.low.configure('lowShelf', 120, 0.707, lowDb, this.sr); this.last[0] = lowDb; }
    if (midDb !== this.last[1] || midFreq !== this.last[3]) {
      this.mid.configure('peaking', midFreq, 0.9, midDb, this.sr); this.last[1] = midDb; this.last[3] = midFreq;
    }
    if (highDb !== this.last[2]) { this.high.configure('highShelf', 6000, 0.707, highDb, this.sr); this.last[2] = highDb; }
  }
  get isFlat() { return this.low.isIdentity && this.mid.isIdentity && this.high.isIdentity; }
  reset() { this.low.reset(); this.mid.reset(); this.high.reset(); }
  process(l, r) {
    if (!this.low.isIdentity) { this.low.process(l, r); l = this.low.outL; r = this.low.outR; }
    if (!this.mid.isIdentity) { this.mid.process(l, r); l = this.mid.outL; r = this.mid.outR; }
    if (!this.high.isIdentity) { this.high.process(l, r); l = this.high.outL; r = this.high.outR; }
    this.outL = l; this.outR = r;
  }
}

/** ADSR mit linearem Attack und exponentiellem Decay/Release; Mindestzeiten gegen Klicks. */
export class ADSREnvelope {
  constructor() {
    this.stage = 0; // 0 idle, 1 attack, 2 decay, 3 sustain, 4 release
    this.level = 0;
    this.attackInc = 1; this.decayCoeff = 0; this.releaseCoeff = 0; this.sustain = 1;
  }
  configure(attack, decay, sustain, release, sr) {
    this.attackInc = 1 / (Math.max(attack, 0.0005) * sr);
    this.decayCoeff = Math.exp(Math.log(0.001) / (Math.max(decay, 0.001) * sr));
    this.releaseCoeff = Math.exp(Math.log(0.001) / (Math.max(release, 0.002) * sr));
    this.sustain = clamp(sustain, 0, 1);
  }
  noteOn() { this.stage = 1; }
  noteOff() { if (this.stage !== 0) this.stage = 4; }
  reset() { this.stage = 0; this.level = 0; }
  get isActive() { return this.stage !== 0; }
  next() {
    switch (this.stage) {
      case 0: return 0;
      case 1:
        this.level += this.attackInc;
        if (this.level >= 1) { this.level = 1; this.stage = 2; }
        break;
      case 2:
        this.level = this.sustain + (this.level - this.sustain) * this.decayCoeff;
        if (Math.abs(this.level - this.sustain) < 0.0001) { this.level = this.sustain; this.stage = 3; }
        break;
      case 3:
        this.level = this.sustain;
        if (this.sustain <= 0.0001) { this.stage = 0; this.level = 0; }
        break;
      case 4:
        this.level *= this.releaseCoeff;
        if (this.level < 0.0001) { this.level = 0; this.stage = 0; }
        break;
    }
    return this.level;
  }
}

export class LFO {
  constructor() { this.phase = 0; this.hold = 0; this.rng = new FastRandom(0xC0FFEE); }
  reset() { this.phase = 0; }
  value(shape) {
    const p = this.phase;
    switch (shape) {
      case 'sine': return Math.sin(2 * Math.PI * p);
      case 'triangle': return p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
      case 'square': return p < 0.5 ? 1 : -1;
      case 'sawUp': return 2 * p - 1;
      case 'sawDown': return 1 - 2 * p;
      case 'sampleHold': return this.hold;
      default: return 0;
    }
  }
  next(shape, rate, sr, samples = 1) {
    const v = this.value(shape);
    this.phase += (rate * samples) / sr;
    if (this.phase >= 1) { this.phase -= Math.floor(this.phase); this.hold = this.rng.nextBipolar(); }
    return v;
  }
}

export function distort(x, drive) {
  if (drive <= 0.0001) return x;
  const g = 1 + drive * drive * 40;
  const norm = 1 / fastTanh(Math.min(g, 3));
  return fastTanh(x * g) * norm * (1 - 0.35 * drive);
}

export class Bitcrusher {
  constructor() { this.counter = 0; this.holdL = 0; this.holdR = 0; this.outL = 0; this.outR = 0; }
  reset() { this.counter = 0; this.holdL = 0; this.holdR = 0; }
  process(l, r, bits, downsample) {
    if (bits >= 15.99 && downsample <= 1.001) { this.outL = l; this.outR = r; return; }
    if (this.counter <= 0) { this.counter += Math.max(downsample, 1); this.holdL = l; this.holdR = r; }
    this.counter -= 1;
    if (bits >= 15.99) { this.outL = this.holdL; this.outR = this.holdR; return; }
    const levels = Math.pow(2, Math.max(bits, 1) - 1);
    this.outL = Math.round(this.holdL * levels) / levels;
    this.outR = Math.round(this.holdR * levels) / levels;
  }
}

export class Compressor {
  constructor(sr = 44100) {
    this.sr = sr;
    this.threshold = 0; this.ratio = 4; this.attack = 0.01; this.release = 0.15; this.makeup = 0; this.knee = 6;
    this.envDb = -120; this.gr = 0; this.outL = 0; this.outR = 0;
    this.updateTimes();
  }
  updateTimes() {
    this.attackCoeff = onePoleCoefficient(Math.max(this.attack, 0.0001), this.sr);
    this.releaseCoeff = onePoleCoefficient(Math.max(this.release, 0.001), this.sr);
  }
  reset() { this.envDb = -120; this.gr = 0; }
  get isActive() { return (this.threshold < -0.05 && this.ratio > 1.01) || Math.abs(this.makeup) > 0.01; }
  gainReduction(x) {
    const r = Math.max(this.ratio, 1);
    const over = x - this.threshold;
    if (2 * over < -this.knee) return 0;
    if (2 * Math.abs(over) <= this.knee) { const t = over + this.knee / 2; return ((1 / r - 1) * t * t) / (2 * this.knee); }
    return (1 / r - 1) * over;
  }
  process(l, r) {
    const inDb = gainToDb(Math.max(Math.abs(l), Math.abs(r)));
    const c = inDb > this.envDb ? this.attackCoeff : this.releaseCoeff;
    this.envDb = inDb + c * (this.envDb - inDb);
    this.gr = this.gainReduction(this.envDb);
    const g = dbToGain(this.gr + this.makeup);
    this.outL = l * g; this.outR = r * g;
  }
}

/** Stereo-Delay mit Feedback, Ping-Pong und Dämpfung (Puffer einmalig angelegt). */
export class StereoDelay {
  constructor(sr) {
    this.sr = sr;
    this.capacity = Math.floor(2.5 * sr) + 4;
    this.bufL = new Float32Array(this.capacity);
    this.bufR = new Float32Array(this.capacity);
    this.w = 0;
    this.smoothed = new SmoothedValue(0.375 * sr, 0.08, sr);
    this.dampL = 0; this.dampR = 0; this.primed = false;
    this.delaySeconds = 0.375; this.feedback = 0.35; this.pingPong = true; this.damping = 0.3;
  }
  reset() { this.bufL.fill(0); this.bufR.fill(0); this.dampL = this.dampR = 0; this.primed = false; }
  _read(buf, d) {
    let pos = this.w - d;
    if (pos < 0) pos += this.capacity;
    const i0 = Math.floor(pos);
    const frac = pos - i0;
    return buf[i0 % this.capacity] * (1 - frac) + buf[(i0 + 1) % this.capacity] * frac;
  }
  process(inL, inR, outL, outR, count) {
    this.smoothed.target = clamp(this.delaySeconds, 0.001, 2.49) * this.sr;
    if (!this.primed) { this.primed = true; this.smoothed.reset(this.smoothed.target); }
    const fb = clamp(this.feedback, 0, 0.95), damp = clamp(this.damping, 0, 0.95);
    for (let i = 0; i < count; i++) {
      const d = this.smoothed.next();
      const yL = this._read(this.bufL, d), yR = this._read(this.bufR, d);
      this.dampL = yL + damp * (this.dampL - yL);
      this.dampR = yR + damp * (this.dampR - yR);
      const fbL = flushDenormal(this.dampL * fb), fbR = flushDenormal(this.dampR * fb);
      if (this.pingPong) {
        this.bufL[this.w] = (inL[i] + inR[i]) * 0.5 + fbR;
        this.bufR[this.w] = fbL;
      } else {
        this.bufL[this.w] = inL[i] + fbL;
        this.bufR[this.w] = inR[i] + fbR;
      }
      outL[i] = yL; outR[i] = yR;
      if (++this.w >= this.capacity) this.w = 0;
    }
  }
}

/** Moduliertes kurzes Delay – echtes Tonhöhen-Vibrato. */
export class VibratoProcessor {
  constructor(sr) {
    this.sr = sr;
    this.capacity = Math.floor(0.03 * sr) + 4;
    this.bufL = new Float32Array(this.capacity);
    this.bufR = new Float32Array(this.capacity);
    this.w = 0; this.outL = 0; this.outR = 0;
  }
  reset() { this.bufL.fill(0); this.bufR.fill(0); }
  process(l, r, mod) {
    this.bufL[this.w] = l; this.bufR[this.w] = r;
    const d = 0.006 * this.sr + mod * 0.005 * this.sr;
    let pos = this.w - d;
    if (pos < 0) pos += this.capacity;
    const i0 = Math.floor(pos) % this.capacity, i1 = (i0 + 1) % this.capacity, f = pos - Math.floor(pos);
    this.outL = this.bufL[i0] * (1 - f) + this.bufL[i1] * f;
    this.outR = this.bufR[i0] * (1 - f) + this.bufR[i1] * f;
    if (++this.w >= this.capacity) this.w = 0;
  }
}

/** Freeverb-Hall (8 Kammfilter + 4 Allpässe je Kanal). */
export class Reverb {
  constructor(sr) {
    const scale = sr / 44100;
    const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    const aps = [556, 441, 341, 225];
    const mk = (n) => ({ buf: new Float32Array(Math.max(1, Math.floor(n * scale))), i: 0, store: 0 });
    this.combL = combs.map(mk); this.combR = combs.map((n) => mk(n + 23));
    this.apL = aps.map(mk); this.apR = aps.map((n) => mk(n + 23));
    this.roomSize = 0.7; this.damping = 0.4; this.width = 1;
  }
  reset() {
    for (const c of [...this.combL, ...this.combR, ...this.apL, ...this.apR]) { c.buf.fill(0); c.store = 0; }
  }
  process(inL, inR, outL, outR, count) {
    const fb = clamp(this.roomSize, 0, 1) * 0.28 + 0.7;
    const damp = clamp(this.damping, 0, 1) * 0.4;
    const w = clamp(this.width, 0, 1);
    const wet1 = w / 2 + 0.5, wet2 = (1 - w) / 2;
    const cl = this.combL, cr = this.combR, al = this.apL, ar = this.apR;
    for (let i = 0; i < count; i++) {
      const input = (inL[i] + inR[i]) * 0.015;
      let sL = 0, sR = 0;
      for (let c = 0; c < 8; c++) {
        let k = cl[c]; let o = k.buf[k.i];
        k.store = flushDenormal(o * (1 - damp) + k.store * damp); k.buf[k.i] = input + k.store * fb;
        if (++k.i >= k.buf.length) k.i = 0; sL += o;
        k = cr[c]; o = k.buf[k.i];
        k.store = flushDenormal(o * (1 - damp) + k.store * damp); k.buf[k.i] = input + k.store * fb;
        if (++k.i >= k.buf.length) k.i = 0; sR += o;
      }
      for (let a = 0; a < 4; a++) {
        let k = al[a]; let b = k.buf[k.i];
        let o = b - sL; k.buf[k.i] = flushDenormal(sL + b * 0.5); if (++k.i >= k.buf.length) k.i = 0; sL = o;
        k = ar[a]; b = k.buf[k.i];
        o = b - sR; k.buf[k.i] = flushDenormal(sR + b * 0.5); if (++k.i >= k.buf.length) k.i = 0; sR = o;
      }
      outL[i] = (sL * wet1 + sR * wet2) * 3;
      outR[i] = (sR * wet1 + sL * wet2) * 3;
    }
  }
}
