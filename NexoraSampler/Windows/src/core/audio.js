// Audio-Ausgabe über Web Audio: AudioContext + AudioWorklet mit der NEXORA-Engine.
import { decodeAudio } from '../engine/audiofile.js';
import { makeSample } from '../engine/engine.js';

export const MAX_SAMPLE_SECONDS = 600;

export class AudioHost {
  constructor() {
    this.ctx = null;
    this.node = null;
    this.pending = [];
    this.onStatus = null;
    this.onReady = null;
    this.error = null;
  }

  get sampleRate() { return this.ctx?.sampleRate ?? 48000; }
  get running() { return this.ctx?.state === 'running'; }
  get latencyMs() { return this.ctx ? ((this.ctx.baseLatency ?? 0) + (this.ctx.outputLatency ?? 0)) * 1000 : 0; }

  async start({ latencyHint = 'interactive', sinkId = '' } = {}) {
    try {
      this.ctx = new AudioContext({ latencyHint });
      await this.ctx.audioWorklet.addModule(new URL('../engine/worklet.js', import.meta.url));
      this.node = new AudioWorkletNode(this.ctx, 'nexora-engine', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
      this.node.connect(this.ctx.destination);
      this.node.port.onmessage = (e) => this.onStatus?.(e.data);
      if (sinkId && this.ctx.setSinkId) await this.ctx.setSinkId(sinkId).catch(() => {});
      const queued = this.pending;
      this.pending = [];
      if (queued.length) this.node.port.postMessage(queued);
      if (this.ctx.state !== 'running') {
        const resume = () => { this.ctx?.resume(); };
        for (const ev of ['pointerdown', 'keydown']) globalThis.addEventListener(ev, resume, { once: true, capture: true });
        this.ctx.resume().catch(() => {});
      }
      this.error = null;
      this.onReady?.();
    } catch (err) {
      this.error = err;
      throw err;
    }
  }

  async restart(opts) {
    const old = this.ctx;
    this.node = null;
    this.ctx = null;
    if (old) await old.close().catch(() => {});
    await this.start(opts);
  }

  send(cmd) {
    if (this.node) this.node.port.postMessage(cmd);
    else this.pending.push(cmd);
  }

  async outputDevices() {
    try {
      const all = await navigator.mediaDevices.enumerateDevices();
      return all.filter((d) => d.kind === 'audiooutput').map((d, i) => ({ id: d.deviceId, name: d.label || `Ausgabegerät ${i + 1}` }));
    } catch {
      return [];
    }
  }

  async setSink(id) {
    if (this.ctx?.setSinkId) await this.ctx.setSinkId(id || '');
  }

  /** Dekodiert WAV/AIFF selbst, alle übrigen Formate (MP3, M4A, FLAC, OGG) über den Browser-Decoder. */
  async decode(bytes, name) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    const tag = String.fromCharCode(u8[0], u8[1], u8[2], u8[3]);
    let channels, sampleRate;
    if (tag === 'RIFF' || tag === 'FORM') {
      const d = decodeAudio(u8);
      channels = d.channels.slice(0, 2);
      sampleRate = d.sampleRate;
    } else {
      const ctx = this.ctx ?? new OfflineAudioContext(2, 1, 48000);
      const copy = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
      const buf = await ctx.decodeAudioData(copy);
      channels = [];
      for (let c = 0; c < Math.min(2, buf.numberOfChannels); c++) channels.push(new Float32Array(buf.getChannelData(c)));
      sampleRate = buf.sampleRate;
    }
    if (!channels.length || !channels[0].length) throw new Error('Die Datei enthält keine Audiodaten.');
    const seconds = channels[0].length / sampleRate;
    if (seconds > MAX_SAMPLE_SECONDS) throw new Error(`Das Sample ist zu lang (${seconds.toFixed(0)} s, maximal ${MAX_SAMPLE_SECONDS} s).`);
    return makeSample(channels, sampleRate, name);
  }
}

/** Wellenform-Übersicht (Spitzenwerte) für Anzeigen. */
export function overview(sample, bins = 320) {
  const out = new Float32Array(bins);
  if (!sample) return out;
  const n = sample.frameCount;
  for (let b = 0; b < bins; b++) {
    const s = Math.floor((b * n) / bins), e = Math.max(s + 1, Math.floor(((b + 1) * n) / bins));
    let m = 0;
    for (let i = s; i < e && i < n; i++) {
      const a = Math.abs(sample.left[i]); if (a > m) m = a;
      if (sample.right !== sample.left) { const r = Math.abs(sample.right[i]); if (r > m) m = r; }
    }
    out[b] = m;
  }
  return out;
}
