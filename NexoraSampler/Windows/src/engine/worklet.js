// AudioWorklet: führt die NEXORA-Engine im Echtzeit-Audio-Thread aus.
import { SamplerEngine } from './engine.js';

class NexoraEngineProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.engine = new SamplerEngine(sampleRate);
    this.blocks = 0;
    this.statusEvery = Math.max(1, Math.round(sampleRate / 128 / 30));
    this.port.onmessage = (e) => {
      const m = e.data;
      if (Array.isArray(m)) for (const x of m) this.engine.handle(x);
      else this.engine.handle(m);
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    const L = out[0];
    const R = out.length > 1 ? out[1] : out[0];
    if (L) this.engine.render(L.length, L, R);
    if (++this.blocks >= this.statusEvery) {
      this.blocks = 0;
      const s = this.engine.status;
      const hits = this.engine.recordedHits.length ? this.engine.recordedHits.splice(0) : null;
      this.port.postMessage({
        type: 'status', currentStep: s.currentStep, transport: s.transport, activeVoices: s.activeVoices,
        peakL: s.peakL, peakR: s.peakR, currentPattern: s.currentPattern, queuedPattern: s.queuedPattern,
        gainReduction: s.gainReduction, songIndex: s.songIndex, position: s.position, padLevels: Array.from(s.padLevels), padTriggers: Array.from(s.padTriggers), hits
      });
    }
    return true;
  }
}

registerProcessor('nexora-engine', NexoraEngineProcessor);

/** Aufnahme (Sampling/Resampling): sammelt Eingangsblöcke und schickt sie gebündelt an die Oberfläche. */
class NexoraRecorderProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.size = 2048;
    this.l = new Float32Array(this.size); this.r = new Float32Array(this.size); this.fill = 0;
    this.stereo = false;
    this.running = true;
    this.port.onmessage = (e) => { if (e.data === 'stop') { this._flush(); this.running = false; this.port.postMessage({ type: 'stopped' }); } };
  }
  _flush() {
    if (!this.fill) return;
    const l = this.l.slice(0, this.fill), r = this.stereo ? this.r.slice(0, this.fill) : null;
    this.port.postMessage({ type: 'audio', l, r }, r ? [l.buffer, r.buffer] : [l.buffer]);
    this.fill = 0;
  }
  process(inputs) {
    if (!this.running) return false;
    const input = inputs[0];
    if (!input || !input.length) return true;
    const L = input[0], R = input[1] ?? input[0];
    if (input.length > 1) this.stereo = true;
    for (let i = 0; i < L.length; i++) {
      this.l[this.fill] = L[i]; this.r[this.fill] = R[i];
      if (++this.fill === this.size) this._flush();
    }
    return true;
  }
}

registerProcessor('nexora-recorder', NexoraRecorderProcessor);
