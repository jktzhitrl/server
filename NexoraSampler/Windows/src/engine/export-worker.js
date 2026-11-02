// Offline-Export in einem eigenen Thread (Web Worker), damit die Oberfläche bedienbar bleibt.
import { renderOffline, normalizeResult } from './offline.js';
import { encodeAudio } from './audiofile.js';

self.onmessage = (e) => {
  const { request, settings } = e.data;
  try {
    let last = 0;
    const result = renderOffline(request, (p) => {
      if (p - last > 0.02) { last = p; self.postMessage({ type: 'progress', value: p }); }
      return true;
    });
    if (settings.normalize) normalizeResult(result);
    const data = encodeAudio(result.left, result.right, result.sampleRate, settings.format, settings.bitDepth);
    self.postMessage({ type: 'done', data, duration: result.left.length / result.sampleRate }, [data.buffer]);
  } catch (err) {
    self.postMessage({ type: 'error', message: err.message ?? String(err) });
  }
};
