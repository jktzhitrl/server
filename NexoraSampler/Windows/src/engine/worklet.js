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
        gainReduction: s.gainReduction, padLevels: Array.from(s.padLevels), padTriggers: Array.from(s.padTriggers), hits
      });
    }
    return true;
  }
}

registerProcessor('nexora-engine', NexoraEngineProcessor);
