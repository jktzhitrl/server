// Dialoge: Audio-Export, Einstellungen, Hinweise.
import { h, setText, onUpdate } from './dom.js';
import { slotName, PATTERN_SLOTS } from '../engine/model.js';

export function buildDialogs(c, root) {
  let current = null;
  onUpdate(() => {
    const want = c.notice ? 'notice' : c.dialog;
    if (want === current && want !== 'notice') return;
    if (want === 'notice' && current === 'notice' && root.__notice === c.notice) return;
    current = want;
    root.__notice = c.notice;
    root.replaceChildren();
    if (want === 'notice') root.append(noticeDialog(c));
    else if (want === 'export') root.append(exportDialog(c));
    else if (want === 'settings') root.append(settingsDialog(c));
    else if (want === 'slice') root.append(sliceDialog(c));
  });
}

const modal = (onClose, ...children) => {
  const back = h('div', { class: 'modal-backdrop' }, h('div', { class: 'modal' }, ...children));
  back.addEventListener('pointerdown', (e) => { if (e.target === back) onClose(); });
  return back;
};
const frow = (label, control) => h('div', { class: 'frow' }, h('span', { text: label }), control);
const select = (options, value, onChange) => {
  const s = h('select', { class: 'ui-select' }, ...options.map(([v, t]) => h('option', { value: String(v), text: t })));
  s.value = String(value);
  s.addEventListener('change', () => onChange(s.value));
  return s;
};

function sliceDialog(c) {
  const close = () => { c.dialog = null; c.changed(); };
  const src = c.selectedPad;
  const sample = c.padSamples[src];
  if (!sample) {
    return modal(close, h('h2', { text: 'Slice' }), h('p', { text: 'Das ausgewählte Pad ist leer. Laden Sie zuerst ein Sample oder einen Song auf das Pad.' }),
      h('div', { class: 'actions' }, h('button', { class: 'ui-btn primary', text: 'OK', onclick: close })));
  }
  const o = { mode: 'transients', count: 8, sensitivity: 0.5, startPad: src, makePattern: true };
  const wave = h('canvas', { width: 1120, height: 240 });
  const box = h('div', { class: 'slice-wave' }, wave);
  const info = h('p', { class: 'muted' });
  const st = c.project.pads[src].settings;
  const peaks = c.padWaveforms[src];
  const draw = () => {
    const g = wave.getContext('2d');
    const W = wave.width, H = wave.height;
    g.clearRect(0, 0, W, H);
    const a = st.start, b = st.end;
    g.fillStyle = '#9ad7ff';
    if (peaks) {
      const n = peaks.length;
      for (let x = 0; x < W; x++) {
        const pos = a + ((b - a) * x) / W;
        const v = peaks[Math.min(n - 1, Math.floor(pos * n))] ?? 0;
        const hh = Math.max(1, v * H * 0.9);
        g.fillRect(x, (H - hh) / 2, 1, hh);
      }
    }
    box.querySelectorAll('i').forEach((el) => el.remove());
    const parts = c.previewSlices(o);
    parts.forEach((p, i) => {
      const x = ((p.start - a) / (b - a || 1)) * 100;
      box.append(h('i', { style: { left: `${x.toFixed(2)}%` } }, h('span', { text: String(o.startPad + i + 1) })));
    });
    const last = Math.min(16, o.startPad + parts.length);
    setText(info, `${parts.length} Slices → Pads ${o.startPad + 1}–${last}${o.makePattern ? ' · Pattern ' + slotName(c.project.sequencer.currentPattern) + ' wird belegt' : ''}. Bereich: Start/Ende des Pads (${Math.round(a * 100)}–${Math.round(b * 100)} %).`);
  };
  const modeSel = select([['transients', 'Nach Anschlägen (Transienten)'], ['equal', 'Gleichmäßig']], o.mode, (v) => { o.mode = v; refresh(); });
  const countSel = select([[2, '2'], [4, '4'], [8, '8'], [16, '16']], o.count, (v) => { o.count = Number(v); draw(); });
  const sens = h('input', { type: 'range', min: 0, max: 1, step: 0.05, value: o.sensitivity });
  sens.addEventListener('input', () => { o.sensitivity = Number(sens.value); draw(); });
  const startSel = select(Array.from({ length: 16 }, (_, i) => [i, `Pad ${i + 1}`]), o.startPad, (v) => { o.startPad = Number(v); draw(); });
  const pat = h('input', { type: 'checkbox' }); pat.checked = o.makePattern;
  pat.addEventListener('change', () => { o.makePattern = pat.checked; draw(); });
  const countRow = frow('Anzahl', countSel), sensRow = frow('Empfindlichkeit', sens);
  const refresh = () => { countRow.style.display = o.mode === 'equal' ? '' : 'none'; sensRow.style.display = o.mode === 'equal' ? 'none' : ''; draw(); };
  const go = h('button', { class: 'ui-btn primary', text: 'Slicen', onclick: () => { if (c.sliceSelectedPad(o)) close(); } });
  const node = modal(close,
    h('h2', { text: `Slice – Pad ${src + 1}: ${c.project.pads[src].name}` }),
    h('p', { text: 'Zerlegt das Sample (z. B. einen Drum-Loop oder einen Song-Ausschnitt) in Stücke und legt jedes Stück auf ein eigenes Pad. Alle Pads verwenden dieselbe Datei – es wird kein zusätzlicher Speicher belegt.' }),
    box, info,
    frow('Modus', modeSel), countRow, sensRow, frow('Ab Pad', startSel),
    frow('Pattern erzeugen (Sample = ein Pattern-Durchlauf)', pat),
    h('div', { class: 'actions' }, h('button', { class: 'ui-btn', text: 'Abbrechen', onclick: close }), go));
  refresh();
  return node;
}

function noticeDialog(c) {
  const close = () => { c.notice = null; c.changed(); };
  return modal(close, h('h2', { text: c.notice.title }), h('p', { style: { whiteSpace: 'pre-wrap' }, text: c.notice.message }),
    h('div', { class: 'actions' }, h('button', { class: 'ui-btn primary', text: 'OK', onclick: close })));
}

function exportDialog(c) {
  const s = { ...c.project.export };
  const close = () => { if (c.exportProgress == null) { c.dialog = null; c.changed(); } };
  const chain = h('input', { class: 'ui-input', value: c.project.patternChain.map(slotName).join(' '), style: { width: '160px' }, placeholder: 'z. B. A A B A' });
  const chainRow = frow('Pattern-Kette', chain);
  const applyChain = () => {
    const slots = [...chain.value.toUpperCase()].map((ch) => 'ABCDEFGH'.indexOf(ch)).filter((i) => i >= 0 && i < PATTERN_SLOTS);
    if (slots.length) c.project.patternChain = slots;
  };
  const loops = h('input', { class: 'ui-input', type: 'number', min: 1, max: 64, value: s.loops, style: { width: '70px' } });
  const tail = h('input', { class: 'ui-input', type: 'number', min: 0, max: 30, value: s.tailSeconds, style: { width: '70px' } });
  const chainBox = h('input', { type: 'checkbox' }); chainBox.checked = s.exportChain;
  const norm = h('input', { type: 'checkbox' }); norm.checked = s.normalize;
  const warn = h('p', { style: { color: '#f6a', margin: '6px 0 0' } });
  const bar = h('i', { style: { width: '0%' } });
  const progress = h('div', { class: 'progress', style: { display: 'none' } }, bar);
  const exportBtn = h('button', { class: 'ui-btn primary', text: 'Exportieren …' });
  const cancelBtn = h('button', { class: 'ui-btn', text: 'Schließen' });
  const refresh = () => {
    setText(warn, s.format === 'aiff' && s.bitDepth === 'float32' ? 'AIFF wird mit 16 oder 24 Bit geschrieben – bitte Bittiefe wählen.' : '');
    exportBtn.disabled = c.exportProgress != null || (s.format === 'aiff' && s.bitDepth === 'float32');
    chainRow.style.display = chainBox.checked ? '' : 'none';
  };
  onUpdate(() => {
    const p = c.exportProgress;
    progress.style.display = p == null ? 'none' : 'block';
    bar.style.width = `${Math.round((p ?? 0) * 100)}%`;
    setText(cancelBtn, p == null ? 'Schließen' : 'Abbrechen');
    exportBtn.disabled = p != null || (s.format === 'aiff' && s.bitDepth === 'float32');
  });
  cancelBtn.onclick = () => (c.exportProgress != null ? c.cancelExport() : close());
  exportBtn.onclick = () => {
    applyChain();
    s.loops = Math.max(1, Math.min(64, Number(loops.value) || 1));
    s.tailSeconds = Math.max(0, Math.min(30, Number(tail.value) || 0));
    s.exportChain = chainBox.checked; s.normalize = norm.checked;
    c.exportAudio({ ...s });
  };
  chainBox.addEventListener('change', refresh);
  const node = modal(close,
    h('h2', { text: 'Audio exportieren' }),
    h('p', { text: 'Das Pattern wird mit derselben Audio-Engine gerendert, die Sie hören – inklusive aller Pad- und Master-Effekte.' }),
    frow('Format', select([['wav', 'WAV'], ['aiff', 'AIFF']], s.format, (v) => { s.format = v; refresh(); })),
    frow('Abtastrate', select([[44100, '44,1 kHz'], [48000, '48 kHz']], s.sampleRate, (v) => { s.sampleRate = Number(v); })),
    frow('Bittiefe', select([['pcm16', '16 Bit'], ['pcm24', '24 Bit'], ['float32', '32 Bit Float']], s.bitDepth, (v) => { s.bitDepth = v; refresh(); })),
    frow('Wiederholungen', loops), frow('Ausklingzeit (s, max.)', tail),
    frow('Pattern-Kette exportieren', chainBox), chainRow,
    frow('Auf −0,3 dBFS normalisieren', norm), frow('Kanäle', h('span', { text: 'Stereo' })),
    warn, progress,
    h('div', { class: 'actions' }, cancelBtn, exportBtn));
  refresh();
  return node;
}

function settingsDialog(c) {
  const close = () => { c.dialog = null; c.changed(); };
  const p = c.prefs;
  const box = (key) => { const b = h('input', { type: 'checkbox' }); b.checked = !!p[key]; b.addEventListener('change', () => c.setPref(key, b.checked)); return b; };
  const range = (key, min, max, step) => { const r = h('input', { type: 'range', min, max, step, value: p[key] }); r.addEventListener('input', () => c.setPref(key, Number(r.value))); return r; };
  const devices = h('select', { class: 'ui-select', style: { maxWidth: '230px' } }, h('option', { value: '', text: 'Systemstandard' }));
  c.audio.outputDevices().then((list) => {
    for (const d of list) if (d.id !== 'default') devices.append(h('option', { value: d.id, text: d.name }));
    devices.value = p.sinkId || '';
  });
  devices.addEventListener('change', async () => { c.setPref('sinkId', devices.value); await c.audio.setSink(devices.value).catch(() => {}); });
  const latency = select([['interactive', 'Niedrig (Live-Spiel)'], ['balanced', 'Ausgewogen'], ['playback', 'Hoch (stabil)']], p.latencyHint, async (v) => {
    c.setPref('latencyHint', v);
    await c.audio.restart({ latencyHint: v, sinkId: p.sinkId });
    c.pushFullState();
  });
  const latInfo = h('span');
  onUpdate(() => setText(latInfo, `${(c.audio.sampleRate / 1000).toFixed(1)} kHz · ca. ${c.audio.latencyMs.toFixed(1)} ms`));
  const name = h('input', { class: 'ui-input', value: c.project.name });
  name.addEventListener('change', () => { c.project.name = name.value.trim() || 'Untitled'; c.markDirty(); c.changed(); });
  const poly = h('input', { class: 'ui-input', type: 'number', min: 1, max: 64, value: c.project.engine.polyphony, style: { width: '70px' } });
  poly.addEventListener('change', () => c.updateEngine((e) => { e.polyphony = Math.max(1, Math.min(64, Number(poly.value) || 32)); }));
  return modal(close,
    h('h2', { text: 'Einstellungen' }),
    h('div', { class: 'section-title', text: 'Audio' }),
    frow('Ausgabegerät', devices), frow('Latenz', latency), frow('Abtastrate / Latenz', latInfo),
    h('div', { class: 'section-title', text: 'Projekt' }),
    frow('Projektname', name),
    frow('Polyphonie (Stimmen)', poly),
    frow('Voice-Stealing', select([['oldest', 'Älteste Stimme'], ['quietest', 'Leiseste Stimme'], ['samePad', 'Gleiches Pad zuerst'], ['none', 'Kein Stealing']],
      c.project.engine.stealMode, (v) => c.updateEngine((e) => { e.stealMode = v; }))),
    h('div', { class: 'section-title', text: 'Bedienung' }),
    frow('Gehäusefarbe', select([['crimson', 'Crimson (Metallic-Rot)'], ['lilac', 'Lilac (Pastell-Lila)']], p.theme, (v) => c.setPref('theme', v))),
    frow('Anschlagstärke über Klickposition', box('velocityFromPosition')),
    frow('Anschlagstärke Tastatur', range('keyboardVelocity', 0.1, 1, 0.01)),
    frow('Angeschlagenes Pad auswählen', box('selectOnHit')),
    frow('MIDI-Eingang aktiv', box('midiEnabled')),
    h('div', { class: 'section-title', text: 'Bibliothek' }),
    frow('Importe in die Bibliothek kopieren', box('copyImports')),
    frow('Beim Auswählen vorhören', box('autoPreview')),
    frow('Lautstärke Vorhören', range('previewVolume', 0, 1, 0.01)),
    h('p', { style: { marginTop: '12px' }, text: 'Tasten: Q W E R T Y U I = Pads 1–8, A S D F G H J K = Pads 9–16, Leertaste = Play/Stop.' }),
    h('div', { class: 'actions' }, h('button', { class: 'ui-btn primary', text: 'Fertig', onclick: close })));
}
