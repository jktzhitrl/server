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
