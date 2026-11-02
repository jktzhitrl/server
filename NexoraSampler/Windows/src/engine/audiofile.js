// WAV/AIFF schreiben und lesen (Portierung von AudioFileWriter/AudioFileReader).

import { clamp, FastRandom } from './dsp.js';

function extended80(value) {
  const bytes = new Uint8Array(10);
  if (value <= 0) return bytes;
  let exponent = Math.floor(Math.log2(value));
  let mantissa = value / Math.pow(2, exponent);
  while (mantissa >= 2) { mantissa /= 2; exponent++; }
  while (mantissa < 1) { mantissa *= 2; exponent--; }
  const biased = exponent + 16383;
  bytes[0] = biased >> 8; bytes[1] = biased & 0xff;
  let m = BigInt(Math.round(mantissa * 2 ** 52)) << 11n;
  for (let i = 9; i >= 2; i--) { bytes[i] = Number(m & 0xffn); m >>= 8n; }
  return bytes;
}

function parseExtended(b, o) {
  const exponent = (((b[o] & 0x7f) << 8) | b[o + 1]) - 16383;
  let m = 0n;
  for (let i = 0; i < 8; i++) m = (m << 8n) | BigInt(b[o + 2 + i]);
  return Number(m) / 2 ** 63 * Math.pow(2, exponent);
}

/**
 * Kodiert Stereo-Audio. format: 'wav' | 'aiff', bitDepth: 'pcm16' | 'pcm24' | 'float32'.
 * @returns {Uint8Array}
 */
export function encodeAudio(left, right, sampleRate, format, bitDepth, { dither = true, mono = false } = {}) {
  const frames = mono ? left.length : Math.min(left.length, right.length);
  if (!frames) throw new Error('Es sind keine Audiodaten vorhanden.');
  if (format === 'aiff' && bitDepth === 'float32') throw new Error('AIFF unterstützt 16 oder 24 Bit. Für 32-Bit-Float bitte WAV wählen.');
  const channels = mono ? 1 : 2;
  const bits = bitDepth === 'pcm16' ? 16 : bitDepth === 'pcm24' ? 24 : 32;
  const bps = bits / 8;
  const big = format === 'aiff';
  const pcmSize = frames * channels * bps;
  const headerSize = format === 'wav' ? 44 : 54;
  const pad = pcmSize % 2;
  const out = new Uint8Array(headerSize + pcmSize + pad);
  const dv = new DataView(out.buffer);
  const ascii = (o, s) => { for (let i = 0; i < 4; i++) out[o + i] = s.charCodeAt(i); };
  if (format === 'wav') {
    ascii(0, 'RIFF'); dv.setUint32(4, 36 + pcmSize + pad, true); ascii(8, 'WAVE');
    ascii(12, 'fmt '); dv.setUint32(16, 16, true); dv.setUint16(20, bitDepth === 'float32' ? 3 : 1, true);
    dv.setUint16(22, channels, true); dv.setUint32(24, sampleRate, true);
    dv.setUint32(28, sampleRate * channels * bps, true); dv.setUint16(32, channels * bps, true); dv.setUint16(34, bits, true);
    ascii(36, 'data'); dv.setUint32(40, pcmSize, true);
  } else {
    ascii(0, 'FORM'); dv.setUint32(4, 4 + 8 + 18 + 8 + 8 + pcmSize + pad, false); ascii(8, 'AIFF');
    ascii(12, 'COMM'); dv.setUint32(16, 18, false); dv.setUint16(20, channels, false);
    dv.setUint32(22, frames, false); dv.setUint16(26, bits, false); out.set(extended80(sampleRate), 28);
    ascii(38, 'SSND'); dv.setUint32(42, 8 + pcmSize, false); dv.setUint32(46, 0, false); dv.setUint32(50, 0, false);
  }
  const rng = new FastRandom(0xDEC0DE);
  let o = headerSize;
  for (let i = 0; i < frames; i++) {
    for (let c = 0; c < channels; c++) {
      const x = c === 0 ? left[i] : right[i];
      if (bitDepth === 'pcm16') {
        let v = x * 32767;
        if (dither) v += (rng.nextBipolar() + rng.nextBipolar()) * 0.5;
        dv.setInt16(o, clamp(Math.round(v), -32768, 32767), !big); o += 2;
      } else if (bitDepth === 'pcm24') {
        let v = clamp(Math.round(clamp(x, -1, 1) * 8388607), -8388608, 8388607);
        if (v < 0) v += 0x1000000;
        if (big) { out[o] = (v >> 16) & 0xff; out[o + 1] = (v >> 8) & 0xff; out[o + 2] = v & 0xff; }
        else { out[o] = v & 0xff; out[o + 1] = (v >> 8) & 0xff; out[o + 2] = (v >> 16) & 0xff; }
        o += 3;
      } else {
        dv.setFloat32(o, x, !big); o += 4;
      }
    }
  }
  return out;
}

/** Dekodiert WAV (PCM 8/16/24/32, Float 32/64) und AIFF/AIFC (PCM, fl32). */
export function decodeAudio(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const tag = (o) => String.fromCharCode(b[o], b[o + 1], b[o + 2], b[o + 3]);
  if (b.length < 12) throw new Error('Die Audiodatei ist beschädigt.');
  let channels = 0, sampleRate = 0, bits = 0, isFloat = false, big = false, dataStart = -1, dataEnd = -1;
  if (tag(0) === 'RIFF') {
    let o = 12, fmt = 0;
    while (o + 8 <= b.length) {
      const id = tag(o), size = dv.getUint32(o + 4, true), body = o + 8;
      if (id === 'fmt ') {
        fmt = dv.getUint16(body, true); channels = dv.getUint16(body + 2, true);
        sampleRate = dv.getUint32(body + 4, true); bits = dv.getUint16(body + 14, true);
        if (fmt === 0xfffe && size >= 26) fmt = dv.getUint16(body + 24, true);
      } else if (id === 'data') { dataStart = body; dataEnd = Math.min(body + size, b.length); }
      o = body + size + (size % 2);
    }
    if (fmt !== 1 && fmt !== 3) throw new Error(`Nicht unterstütztes WAV-Format (${fmt}).`);
    isFloat = fmt === 3;
  } else if (tag(0) === 'FORM') {
    const form = tag(8);
    if (form !== 'AIFF' && form !== 'AIFC') throw new Error('Nicht unterstütztes AIFF-Format.');
    big = true;
    let o = 12;
    while (o + 8 <= b.length) {
      const id = tag(o), size = dv.getUint32(o + 4, false), body = o + 8;
      if (id === 'COMM') {
        channels = dv.getUint16(body, false); bits = dv.getUint16(body + 6, false); sampleRate = parseExtended(b, body + 8);
        if (form === 'AIFC' && size >= 22) {
          const comp = tag(body + 18);
          if (comp === 'fl32' || comp === 'FL32') { isFloat = true; bits = 32; } else if (comp !== 'NONE') throw new Error(`AIFC-Kompression ${comp} wird nicht unterstützt.`);
        }
      } else if (id === 'SSND') { dataStart = body + 8 + dv.getUint32(body, false); dataEnd = Math.min(body + size, b.length); }
      o = body + size + (size % 2);
    }
  } else throw new Error('Unbekanntes Audioformat.');
  if (dataStart < 0 || !channels || !bits) throw new Error('Die Audiodatei ist beschädigt.');
  const bps = bits / 8, frameSize = bps * channels;
  const frames = Math.floor((dataEnd - dataStart) / frameSize);
  const out = Array.from({ length: channels }, () => new Float32Array(frames));
  for (let f = 0; f < frames; f++) {
    for (let c = 0; c < channels; c++) {
      const o = dataStart + f * frameSize + c * bps;
      let v;
      if (isFloat) v = bits === 64 ? dv.getFloat64(o, !big) : dv.getFloat32(o, !big);
      else if (bits === 8) v = big ? dv.getInt8(o) / 128 : (b[o] - 128) / 128;
      else if (bits === 16) v = dv.getInt16(o, !big) / 32768;
      else if (bits === 24) {
        let x = big ? (b[o] << 16) | (b[o + 1] << 8) | b[o + 2] : (b[o + 2] << 16) | (b[o + 1] << 8) | b[o];
        if (x & 0x800000) x -= 0x1000000;
        v = x / 8388608;
      } else v = dv.getInt32(o, !big) / 2147483648;
      out[c][f] = v;
    }
  }
  return { sampleRate, channels: out };
}
