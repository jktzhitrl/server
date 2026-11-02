// Ausklappbare Bereiche unter dem Instrument.
import { h, setText, setClass, setStyle, onUpdate, segment, contextMenu, pad2 } from './dom.js';
import { paramKnob } from './knob.js';
import { drawWave } from './body.js';
import { DRAWERS, cycle, LFO_TARGET_NAMES, LFO_SHAPE_NAMES, FILTER_NAMES, MOD_TARGET_NAMES, PLAY_MODE_NAMES, noteName } from '../core/controller.js';
import { PARAMS, slotName, PATTERN_SLOTS, MAX_STEPS, TEMPO_DIVISION_NAMES, QUANTIZE_NAMES, defaultMaster, PAGE_COUNT, STEPS_PER_PAGE,
  MOTION_MODES, motionLaneName, SONG_MAX_LENGTH } from '../engine/model.js';

const dk = (c, id, title, extra = {}) => paramKnob(c, id, { title, size: 34, ...extra });
const dsec = (title, ...children) => {
  const head = h('div', { class: 'h' }, typeof title === 'function' ? '' : title);
  if (typeof title === 'function') onUpdate(() => setText(head, title()));
  return h('div', { class: 'dsec' }, head, ...children);
};
const btn = (text, onClick, opts = {}) => h('button', { class: `ui-btn ${opts.danger ? 'danger' : ''}`, text, onclick: onClick, title: opts.tip ?? '' });
const check = (label, get, set, tip) => {
  const box = h('input', { type: 'checkbox' });
  box.addEventListener('change', () => set(box.checked));
  onUpdate(() => { if (box.checked !== get()) box.checked = get(); });
  return h('label', { class: 'check', title: tip ?? '' }, box, label);
};
/** Liste, die sich nur bei geänderter Signatur neu aufbaut. */
function keyedList(container, signature, build) {
  let last = null;
  onUpdate(() => {
    const sig = signature();
    if (sig === last) return;
    last = sig;
    container.replaceChildren(...build());
  });
  return container;
}

export function buildDrawer(c) {
  const panels = {
    editor: padEditor(c), sequencer: sequencer(c), song: songMotion(c), sampling: samplingPanel(c),
    browser: browser(c), effects: effects(c), kits: kits(c), midi: midiPanel(c)
  };
  const tabs = h('div', { class: 'tabs' },
    ...DRAWERS.map(([id, title]) => {
      const t = h('button', { class: 'tab', text: title, onclick: () => { c.drawer = id; c.changed(); } });
      onUpdate(() => setClass(t, 'on', c.drawer === id));
      return t;
    }),
    h('button', { class: 'tab close', text: '▾', title: 'Bereich schließen', onclick: () => { c.drawer = null; c.changed(); } }));
  const content = h('div', { class: 'content' });
  const el = h('div', { class: 'drawer' }, tabs, content);
  let shown = null;
  onUpdate(() => {
    if (c.drawer !== shown) { shown = c.drawer; content.replaceChildren(...(shown ? [panels[shown]] : [])); }
  });
  return el;
}

// ------------------------------------------------------------ Pad-Editor

function padEditor(c) {
  const sel = () => c.project.pads[c.selectedPad];
  const upd = (fn) => c.updatePad(c.selectedPad, fn);
  const title = h('span', { style: { font: '600 13px var(--mono)', color: 'var(--turquoise)' } });
  const name = h('input', { class: 'ui-input', style: { width: '150px' }, title: 'Pad-Namen ändern (Enter bestätigt)' });
  name.addEventListener('change', () => c.renamePad(c.selectedPad, name.value));
  const key = h('input', { class: 'ui-input', style: { width: '40px' }, maxlength: 1, title: 'Tastaturtaste zum Auslösen' });
  key.addEventListener('input', () => c.setPadKey(c.selectedPad, key.value));
  const midiLabel = h('span', { style: { font: '500 10px var(--mono)' } });
  const learnBtn = btn('Note lernen', () => { c.noteLearnPad = c.noteLearnPad === c.selectedPad ? null : c.selectedPad; c.changed(); });
  const choke = h('select', { class: 'ui-select', title: 'Pads derselben Choke-Gruppe schneiden sich gegenseitig ab' },
    ...Array.from({ length: 9 }, (_, i) => h('option', { value: i, text: i === 0 ? 'Choke –' : `Choke ${i}` })));
  choke.addEventListener('change', () => upd((p) => { p.settings.chokeGroup = Number(choke.value); }));

  const canvas = h('canvas', { width: 860, height: 240 });
  const wave = h('div', { class: 'wave-edit', title: 'Start- und Endmarker ziehen. Audiodateien können direkt hierher gezogen werden.' }, canvas);
  let marker = null;
  const pos = (e) => { const r = wave.getBoundingClientRect(); return Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)); };
  wave.addEventListener('pointerdown', (e) => {
    wave.setPointerCapture(e.pointerId);
    const p = pos(e), s = sel().settings;
    marker = Math.abs(p - s.start) <= Math.abs(p - s.end) ? 'padStart' : 'padEnd';
    c.setParameterValue(marker, p);
  });
  wave.addEventListener('pointermove', (e) => { if (marker) c.setParameterValue(marker, pos(e)); });
  wave.addEventListener('pointerup', () => { marker = null; });
  wave.addEventListener('dragover', (e) => e.preventDefault());
  wave.addEventListener('drop', (e) => { e.preventDefault(); c.handleDrop(e.dataTransfer, c.selectedPad); });
  let waveKey = '';
  onUpdate(() => {
    const p = sel();
    setText(title, `PAD ${pad2(c.selectedPad + 1)}`);
    if (document.activeElement !== name) name.value = p.name;
    if (document.activeElement !== key) key.value = p.keyboardKey.toUpperCase();
    setText(midiLabel, `MIDI ${noteName(c.project.midi.padNotes[c.selectedPad])}`);
    setText(learnBtn, c.noteLearnPad === c.selectedPad ? 'Warte auf Note …' : 'Note lernen');
    if (choke.value !== String(p.settings.chokeGroup)) choke.value = String(p.settings.chokeGroup);
    const wf = c.padWaveforms[c.selectedPad];
    const k = `${c.selectedPad}|${p.settings.start}|${p.settings.end}|${p.settings.reverse}|${wf ? wf[5] + ':' + wf[50] : 'x'}`;
    if (k !== waveKey) { waveKey = k; drawWave(canvas, wf, p.settings, false); }
  });

  const left = h('div', { style: { width: '440px', display: 'flex', flexDirection: 'column', gap: '10px' } },
    h('div', { class: 'row' }, title, name, btn('Laden …', () => c.chooseSampleForSelectedPad(), { tip: 'Audiodatei auf dieses Pad laden (Strg+L)' }),
      btn('Leeren', () => c.clearPad(c.selectedPad)),
      btn('Slice …', () => { c.dialog = 'slice'; c.changed(); }, { tip: 'Sample in Stücke zerlegen und auf Pads verteilen' }),
      btn('▶', () => { c.padDown(c.selectedPad, 1); setTimeout(() => c.padUp(c.selectedPad), 300); }, { tip: 'Pad anspielen' })),
    wave,
    h('div', { class: 'row', style: { gap: '14px' } },
      h('span', { class: 'muted', text: 'MODUS' }), segment(Object.entries(PLAY_MODE_NAMES), () => sel().settings.playMode, (v) => upd((p) => { p.settings.playMode = v; })),
      h('span', { class: 'muted', text: 'PITCH' }), segment([['varispeed', 'VARI'], ['timeStretch', 'STRETCH']], () => sel().settings.pitchMode, (v) => upd((p) => { p.settings.pitchMode = v; }))),
    h('div', { class: 'row', style: { gap: '14px' } },
      check('Reverse', () => sel().settings.reverse, (v) => upd((p) => { p.settings.reverse = v; })),
      check('Mono', () => sel().settings.mono, (v) => upd((p) => { p.settings.mono = v; }), 'Neuer Anschlag beendet die vorherige Stimme dieses Pads'),
      check('Insert-FX', () => sel().settings.insertFXOn, (v) => upd((p) => { p.settings.insertFXOn = v; })),
      choke),
    h('div', { class: 'row', style: { gap: '10px' } }, h('span', { text: 'Taste' }), key, midiLabel, learnBtn));

  const mid = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px' } },
    dsec('Tune · Level', h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap' } },
      dk(c, 'padPitch'), dk(c, 'padFineTune'), dk(c, 'padSpeed'), dk(c, 'padVolume'), dk(c, 'padPan'), dk(c, 'padVelocitySensitivity'))),
    dsec('Envelope', h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap' } },
      dk(c, 'padAttack'), dk(c, 'padDecay'), dk(c, 'padSustain'), dk(c, 'padRelease'))));

  const right = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px' } },
    dsec('Pad Filter · LFO', h('div', { class: 'row', style: { gap: '12px', alignItems: 'flex-start', flexWrap: 'nowrap' } },
      h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px' } },
        segment(Object.entries(FILTER_NAMES), () => sel().settings.filterMode, (v) => upd((p) => { p.settings.filterMode = v; })),
        h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap' } }, dk(c, 'padCutoff'), dk(c, 'padResonance'), dk(c, 'padFilterEnv'))),
      h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px' } },
        segment(Object.entries(LFO_TARGET_NAMES), () => sel().settings.lfoTarget, (v) => upd((p) => { p.settings.lfoTarget = v; })),
        h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap' } }, dk(c, 'padLFORate'), dk(c, 'padLFODepth'),
          segment(Object.entries(LFO_SHAPE_NAMES).slice(0, 3), () => sel().settings.lfoShape, (v) => upd((p) => { p.settings.lfoShape = v; })))))),
    dsec('Pad FX · Sends', h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap' } },
      dk(c, 'padDrive'), dk(c, 'padCrushBits'), dk(c, 'padCrushRate'), dk(c, 'padReverbSend'), dk(c, 'padDelaySend'))));

  return h('div', { style: { display: 'flex', gap: '18px' } }, left, mid, right);
}

// ------------------------------------------------------------ Sequencer

function sequencer(c) {
  const grid = h('div', { class: 'grid' });
  const head = h('div', { class: 'gr hd' }, h('div', { class: 'tn', text: 'TRACK' }), h('div', { style: { width: '16px', textAlign: 'center' }, text: 'M' }),
    h('div', { style: { width: '16px', textAlign: 'center' }, text: 'S' }));
  const headSteps = [];
  for (let s = 0; s < STEPS_PER_PAGE; s++) { const d = h('div', { style: { width: '34px', textAlign: 'center' }, text: String(s + 1) }); headSteps.push(d); head.append(d); }
  head.append(h('div', { style: { width: '44px', textAlign: 'center' }, text: 'GATE' }));
  grid.append(head);
  for (let t = 0; t < 16; t++) {
    const name = h('div', { class: 'tn', onclick: () => c.selectPad(t) });
    const m = h('button', { class: 'tog m', text: 'M', title: 'Spur stummschalten', onclick: () => c.toggleMute(t) });
    const s = h('button', { class: 'tog s', text: 'S', title: 'Spur solo', onclick: () => c.toggleSolo(t) });
    const row = h('div', { class: 'gr' }, name, m, s);
    const cells = [];
    for (let j = 0; j < STEPS_PER_PAGE; j++) {
      const cell = h('div', { class: `cell ${j % 4 === 0 ? 'beat' : ''}`, title: 'Klick: Schritt an/aus · Umschalt+Klick: Anschlagstärke' });
      const mt = h('i', { class: 'mt' });
      cell.append(mt);
      const stepOf = () => c.stepPage * STEPS_PER_PAGE + j;
      cell.addEventListener('click', (e) => (e.shiftKey ? c.cycleStepVelocity(t, stepOf()) : c.toggleStep(t, stepOf())));
      cells.push([cell, mt]);
      row.append(cell);
    }
    const gateVal = h('span', { style: { width: '22px', textAlign: 'right' } });
    row.append(h('div', { class: 'gate', title: 'Notenlänge in Schritten (Gate-/Loop-Pads)' },
      h('button', { text: '–', onclick: () => c.setTrackGate(t, c.currentPattern.gates[t] - 0.25) }), gateVal,
      h('button', { text: '+', onclick: () => c.setTrackGate(t, c.currentPattern.gates[t] + 0.25) })));
    grid.append(row);
    onUpdate(() => {
      const p = c.currentPattern, seq = c.project.sequencer;
      const playing = c.meters.transport !== 'stopped';
      setText(name, `${pad2(t + 1)} ${c.project.pads[t].name}`);
      setClass(name, 'sel', c.selectedPad === t);
      setClass(m, 'on', seq.trackMutes[t]); setClass(s, 'on', seq.trackSolos[t]);
      cells.forEach(([cell, mt], j) => {
        const st = c.stepPage * STEPS_PER_PAGE + j;
        const step = p.steps[t][st];
        setClass(cell, 'on', step.active);
        setClass(cell, 'cur', playing && c.meters.currentStep === st);
        setClass(cell, 'out', st >= p.length);
        setStyle(cell, 'background', step.active ? `color-mix(in srgb, var(--blue-glow) ${Math.round(35 + 65 * step.velocity)}%, transparent)` : '');
        setStyle(mt, 'display', step.active && Math.abs(step.offset) > 0.01 ? 'block' : 'none');
        setStyle(mt, 'left', `${((0.5 + step.offset) * 32).toFixed(1)}px`);
      });
      setText(gateVal, String(+p.gates[t].toFixed(2)));
    });
  }
  onUpdate(() => headSteps.forEach((d, j) => {
    const i = c.stepPage * STEPS_PER_PAGE + j;
    setText(d, String(i + 1));
    setStyle(d, 'color', c.meters.transport !== 'stopped' && c.meters.currentStep === i ? 'var(--pink)' : '');
  }));
  const pages = h('div', { class: 'seg' }, ...Array.from({ length: PAGE_COUNT }, (_, i) => {
    const b = h('button', { text: `${i * 16 + 1}–${i * 16 + 16}`, onclick: () => c.setStepPage(i), title: `Seite ${i + 1}: Schritte ${i * 16 + 1}–${i * 16 + 16}` });
    onUpdate(() => {
      setClass(b, 'on', c.stepPage === i);
      setStyle(b, 'opacity', i < c.pageCount ? '' : '0.35');
      const playingHere = c.meters.transport !== 'stopped' && Math.floor(c.meters.currentStep / 16) === i;
      setStyle(b, 'box-shadow', playingHere ? 'inset 0 -2px 0 var(--pink)' : '');
    });
    return b;
  }));

  const slots = h('div', { class: 'seg' }, ...Array.from({ length: PATTERN_SLOTS }, (_, i) => {
    const b = h('button', { text: slotName(i), onclick: () => c.selectPattern(i) });
    onUpdate(() => setClass(b, 'on', c.project.sequencer.currentPattern === i));
    return b;
  }));
  const len = h('span');
  onUpdate(() => setText(len, `Länge: ${c.currentPattern.length}`));
  const quant = h('select', { class: 'ui-select' }, ...Object.entries(QUANTIZE_NAMES).map(([k, v]) => h('option', { value: k, text: `Rec-Quantisierung ${v}` })));
  quant.addEventListener('change', () => c.setQuantize(quant.value));
  onUpdate(() => { if (quant.value !== c.project.sequencer.quantize) quant.value = c.project.sequencer.quantize; });
  const presetName = h('input', { class: 'ui-input', placeholder: 'Name', style: { width: '110px' } });
  const presetSelect = h('select', { class: 'ui-select', style: { width: '120px' } });
  keyedList(presetSelect, () => `${c.presetRevision}`, () => {
    c.presets.list('pattern').then((list) => {
      presetSelect.replaceChildren(h('option', { value: '', text: 'Pattern laden …' }), ...list.map((p) => h('option', { value: p.path, text: p.name })));
      presetSelect.__list = list;
    });
    return [h('option', { value: '', text: 'Pattern laden …' })];
  });
  presetSelect.addEventListener('change', () => {
    const info = presetSelect.__list?.find((p) => p.path === presetSelect.value);
    if (info) c.loadPatternPreset(info);
    presetSelect.value = '';
  });

  const side = h('div', { style: { width: '400px', display: 'flex', flexDirection: 'column', gap: '8px' } },
    dsec(() => `PATTERN ${slotName(c.project.sequencer.currentPattern)}`,
      slots,
      h('div', { class: 'row' }, btn('–', () => c.setPatternLength(c.currentPattern.length - 1)), len, btn('+', () => c.setPatternLength(c.currentPattern.length + 1)),
        btn('×2', () => c.setPatternLength(Math.min(MAX_STEPS, c.currentPattern.length * 2)), { tip: 'Länge verdoppeln (bis 64 Schritte)' }), pages),
      h('div', { class: 'row' }, check('Seite folgt Wiedergabe', () => c.followPage, (v) => c.setFollowPage(v)),
        check('Wechsel am Taktende', () => c.project.sequencer.switchAtBarEnd, (v) => { c.project.sequencer.switchAtBarEnd = v; c.markDirty(); })),
      h('div', { class: 'row' }, btn('Kopieren', () => c.copyPattern()), btn('Einfügen', () => c.pastePattern()), btn('Leeren', () => c.clearCurrentPattern()))),
    dsec('Timing', h('div', { class: 'row', style: { gap: '4px', alignItems: 'flex-start' } }, dk(c, 'tempo'), dk(c, 'swing'),
      h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px' } }, quant,
        btn('Pattern quantisieren', () => c.quantizeCurrentPattern(), { tip: 'Entfernt Mikro-Timing und rastet Noten auf das Raster' })))),
    dsec('Pattern-Presets', h('div', { class: 'row' }, presetName,
      btn('Speichern', () => { c.savePatternPreset(presetName.value); presetName.value = ''; }), presetSelect)));
  return h('div', { style: { display: 'flex', gap: '16px' } }, grid, side);
}

// ------------------------------------------------------------ Song & Motion

function songMotion(c) {
  const seq = () => c.project.sequencer;
  const chain = h('div', { class: 'chain' });
  keyedList(chain, () => `${c.project.patternChain.join(',')}|${c.meters.songIndex}|${seq().songMode}|${c.meters.transport}`, () => {
    const list = c.project.patternChain;
    if (!list.length) return [h('span', { class: 'muted', text: 'Noch leer – unten Patterns anhängen.' })];
    return list.map((slot, i) => {
      const active = seq().songMode && c.meters.transport !== 'stopped' && c.meters.songIndex === i;
      const el = h('div', { class: `chip ${active ? 'on' : ''}`, title: 'Klick: Pattern ändern · Rechtsklick: verschieben/entfernen' },
        h('small', { text: String(i + 1) }), h('b', { text: slotName(slot) }));
      el.addEventListener('click', () => c.songSetEntry(i, (slot + 1) % PATTERN_SLOTS));
      el.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        contextMenu(e.clientX, e.clientY, [
          { label: '◀ Nach vorn', action: () => c.songMove(i, -1) },
          { label: 'Nach hinten ▶', action: () => c.songMove(i, 1) },
          ...Array.from({ length: PATTERN_SLOTS }, (_, k) => ({ label: `Pattern ${slotName(k)}`, action: () => c.songSetEntry(i, k) })),
          '-', { label: 'Entfernen', action: () => c.songRemoveAt(i) }
        ]);
      });
      return el;
    });
  });
  const adders = h('div', { class: 'seg' }, ...Array.from({ length: PATTERN_SLOTS }, (_, i) =>
    h('button', { text: `+${slotName(i)}`, title: `Pattern ${slotName(i)} an die Kette anhängen`, onclick: () => c.songAppend(i) })));
  const count = h('span', { class: 'muted' });
  onUpdate(() => {
    const n = c.project.patternChain.length;
    const steps = c.project.patternChain.reduce((a, s) => a + c.project.sequencer.patterns[s].length, 0);
    const secs = (steps * 60) / c.project.bpm / 4;
    setText(count, `${n}/${SONG_MAX_LENGTH} Einträge · ${Math.floor(secs / 60)}:${String(Math.round(secs % 60)).padStart(2, '0')} min`);
  });
  const songSec = dsec('SONG',
    h('div', { class: 'row' }, check('Song-Modus: Patterns laufen in dieser Reihenfolge', () => seq().songMode, (v) => c.setSongMode(v))),
    chain,
    h('div', { class: 'row' }, adders),
    h('div', { class: 'row' }, btn('Letzten entfernen', () => c.songRemoveAt(c.project.patternChain.length - 1)), btn('Leeren', () => c.songClear(), { danger: true }), count),
    h('p', { class: 'muted', text: 'Klick auf einen Eintrag wechselt das Pattern, Rechtsklick verschiebt oder entfernt. Die Kette wird auch beim Export „Pattern-Kette“ verwendet. Am Ende beginnt der Song von vorn.' }));

  const lanes = h('div', { class: 'lanes' });
  keyedList(lanes, () => `${c.project.sequencer.currentPattern}|${c.currentPattern.motion.map((l) => l.parameter + l.pad + l.values.filter((v) => v != null).length).join(',')}|${c.currentPattern.length}`, () => {
    const p = c.currentPattern;
    if (!p.motion.length) return [h('span', { class: 'muted', text: 'Keine Motion-Spuren in diesem Pattern.' })];
    return p.motion.map((lane, i) => {
      const spec = PARAMS[lane.parameter];
      const bars = h('div', { class: 'mbars' });
      for (let s = 0; s < p.length; s++) {
        const v = lane.values[s];
        const n = v == null ? 0 : (v - spec.min) / (spec.max - spec.min || 1);
        bars.append(h('i', { style: { height: v == null ? '1px' : `${Math.max(2, Math.round(n * 18))}px`, opacity: v == null ? '0.25' : '1' } }));
      }
      return h('div', { class: 'lane' }, h('span', { class: 'ln', text: motionLaneName(lane) }), bars,
        h('button', { class: 'ui-btn', text: '×', title: 'Spur löschen', onclick: () => c.removeMotionLane(i) }));
    });
  });
  const motionSec = dsec(() => `MOTION · PATTERN ${slotName(c.project.sequencer.currentPattern)} (${c.currentPattern.motion.length}/24)`,
    h('div', { class: 'row' }, h('span', { class: 'muted', text: 'Wiedergabe' }),
      segment(Object.entries(MOTION_MODES), () => seq().motionMode, (v) => c.setMotionMode(v)),
      btn('Alle löschen', () => c.clearMotion(), { danger: true })),
    lanes,
    h('p', { class: 'muted', text: 'Aufnehmen: ● (REC) und ▶ drücken, dann Regler, Touchpad oder MIDI-Controller bewegen. Die Bewegung wird pro Schritt gespeichert und bei jedem Durchlauf wiederholt. Regler mit Motion-Spur zeigen einen rosa Punkt.' }));
  return h('div', { style: { display: 'flex', gap: '18px', alignItems: 'flex-start' } },
    h('div', { style: { width: '520px' } }, songSec), h('div', { style: { flex: '1' } }, motionSec));
}

// ------------------------------------------------------------ Sampling

function samplingPanel(c) {
  const o = c.sampling;
  const set = (patch) => c.setSampling(patch);
  const devices = h('select', { class: 'ui-select', style: { maxWidth: '260px' } });
  keyedList(devices, () => o.devices.map((d) => d.id).join('|'), () =>
    [h('option', { value: '', text: 'Standard-Eingang' }), ...o.devices.filter((d) => d.id).map((d) => h('option', { value: d.id, text: d.name }))]);
  devices.addEventListener('change', () => set({ deviceId: devices.value }));
  onUpdate(() => { if (devices.value !== o.deviceId) devices.value = o.deviceId; devices.disabled = o.source !== 'input' || o.active; });
  const thresholds = [['', 'Sofort'], ['-50', 'ab −50 dB'], ['-40', 'ab −40 dB'], ['-30', 'ab −30 dB'], ['-20', 'ab −20 dB']];
  const thr = h('select', { class: 'ui-select' }, ...thresholds.map(([v, t]) => h('option', { value: v, text: t })));
  thr.addEventListener('change', () => set({ thresholdDb: thr.value === '' ? null : Number(thr.value) }));
  onUpdate(() => { const v = o.thresholdDb == null ? '' : String(o.thresholdDb); if (thr.value !== v) thr.value = v; });
  const lengths = [[10, '10 s'], [30, '30 s'], [60, '1 min'], [300, '5 min'], [600, '10 min']];
  const maxLen = h('select', { class: 'ui-select' }, ...lengths.map(([v, t]) => h('option', { value: String(v), text: `max. ${t}` })));
  maxLen.addEventListener('change', () => set({ maxSeconds: Number(maxLen.value) }));
  onUpdate(() => { if (maxLen.value !== String(o.maxSeconds)) maxLen.value = String(o.maxSeconds); });
  const target = h('select', { class: 'ui-select' }, ...Array.from({ length: 16 }, (_, i) => h('option', { value: String(i), text: `Pad ${i + 1}` })));
  target.addEventListener('change', () => set({ targetPad: Number(target.value) }));
  onUpdate(() => {
    const v = String(o.targetPad);
    if (target.value !== v) target.value = v;
    [...target.options].forEach((op, i) => { op.text = `Pad ${i + 1} · ${c.padSamples[i] ? c.project.pads[i].name : 'leer'}`; });
  });
  const recBtn = h('button', { class: 'ui-btn rec-btn' });
  recBtn.addEventListener('click', () => (o.active ? c.stopSampling() : c.startSampling()));
  onUpdate(() => {
    setText(recBtn, o.active ? '■ Stopp' : '● Aufnahme starten');
    setClass(recBtn, 'on', o.active);
  });
  const meter = h('div', { class: 'rmeter' }, h('i'));
  const status = h('span', { class: 'muted' });
  onUpdate(() => {
    const db = o.level > 0 ? 20 * Math.log10(o.level) : -90;
    setStyle(meter.firstChild, 'width', `${Math.max(0, Math.min(100, ((db + 60) / 60) * 100)).toFixed(0)}%`);
    setStyle(meter.firstChild, 'background', db > -1 ? 'var(--led-red)' : 'var(--turquoise)');
    setText(status, o.active ? (o.state === 'armed' ? 'Wartet auf Signal …' : `Aufnahme läuft · ${o.seconds.toFixed(1)} s`) : 'Bereit');
  });
  const recSec = dsec('AUFNAHME (SAMPLING)',
    h('div', { class: 'row' }, h('span', { class: 'muted', text: 'Quelle' }),
      segment([['input', 'Mikrofon / Line-In'], ['output', 'Resampling (eigener Ausgang)']], () => o.source, (v) => { if (!o.active) set({ source: v }); })),
    h('div', { class: 'row' }, devices, btn('Geräte suchen', () => c.refreshInputDevices())),
    h('div', { class: 'row' }, thr, maxLen, target),
    h('div', { class: 'row' },
      check('Mithören', () => o.monitor, (v) => set({ monitor: v }), 'Eingang über die Lautsprecher hören (Vorsicht vor Rückkopplung)'),
      check('Wiedergabe mitstarten', () => o.startPlayback, (v) => set({ startPlayback: v }), 'Beim Resampling startet der Sequencer mit der Aufnahme und stoppt mit ihr')),
    h('div', { class: 'row' }, recBtn, meter, status),
    h('p', { class: 'muted', text: 'Mikrofon / Line-In: nimmt über das gewählte Audiogerät auf. Resampling: nimmt alles auf, was NEXORA gerade spielt – inklusive Touchpad-Bewegungen und Effekten. Die Aufnahme landet auf dem Ziel-Pad und wird beim Speichern ins Projekt kopiert.' }));
  const resSec = dsec('PATTERN RESAMPLEN',
    h('p', { class: 'muted', text: 'Rendert das aktuelle Pattern einmal (ohne Ausklang, nahtlos loopbar) mit allen Effekten auf das Ziel-Pad – z. B. um einen Beat als Loop weiterzuverarbeiten oder Pads freizumachen.' }),
    h('div', { class: 'row' }, (() => {
      const b = btn('', () => c.resamplePattern(o.targetPad));
      onUpdate(() => { setText(b, c.resampling ? 'Rendert …' : `Pattern ${slotName(c.project.sequencer.currentPattern)} → Pad ${o.targetPad + 1}`); b.disabled = c.resampling; });
      return b;
    })()));
  let asked = false;
  onUpdate(() => { if (!asked && c.drawer === 'sampling') { asked = true; c.refreshInputDevices(); } });
  return h('div', { style: { display: 'flex', gap: '18px', alignItems: 'flex-start' } },
    h('div', { style: { width: '640px' } }, recSec), h('div', { style: { width: '380px' } }, resSec));
}

// ------------------------------------------------------------ Sample-Browser

function browser(c) {
  const lib = () => c.library;
  const collections = h('div', { class: 'list', style: { width: '210px', height: '196px' } });
  keyedList(collections, () => `${c.libraryRevision}|${c.selectedCollection}|${lib().userCollections.map((x) => x.name + x.items.length).join(',')}`, () => {
    const row = (col, factory) => {
      const li = h('div', { class: `li ${c.selectedCollection === col.id ? 'sel' : ''}`, onclick: () => { c.selectedCollection = col.id; c.searchText = ''; c.libraryRevision++; c.changed(); } },
        h('span', { text: factory ? '■' : '▣', style: { color: factory ? 'var(--pink)' : 'var(--turquoise)' } }),
        h('span', { class: 'grow', text: factory ? col.name.replace(/^Factory · /, '') : col.name }),
        h('span', { class: 'dim', text: String(col.items.length) }));
      return li;
    };
    return [h('div', { class: 'sechead', text: 'Werks-Bibliothek' }), ...lib().factoryCollections.map((col) => row(col, true)),
      h('div', { class: 'sechead', text: 'Eigene Bibliotheken' }), ...lib().userCollections.map((col) => row(col, false))];
  });
  const newName = h('input', { class: 'ui-input', placeholder: 'Neue Bibliothek', style: { flex: 1 } });
  const items = h('div', { class: 'list', style: { flex: 1, height: '206px' } });
  items.addEventListener('dragover', (e) => { if (e.dataTransfer.types.includes('Files')) e.preventDefault(); });
  items.addEventListener('drop', (e) => { if (e.dataTransfer.files?.length) { e.preventDefault(); c.importDropped(e.dataTransfer); } });
  keyedList(items, () => `${c.libraryRevision}|${c.selectedCollection}|${c.searchText}|${c.selectedItem}`, () => {
    const list = c.visibleItems;
    if (!list.length) return [h('div', { class: 'sechead', style: { padding: '20px' }, text: 'Audiodateien aus dem Explorer hierher ziehen oder „Importieren …“ wählen' })];
    return list.map((item) => {
      const li = h('div', { class: `li ${c.selectedItem === item.id ? 'sel' : ''}`, draggable: 'true', title: 'Doppelklick: auf ausgewähltes Pad laden · auf ein Pad ziehen' },
        h('span', { text: '∿', style: { color: 'var(--turquoise)' } }), h('span', { class: 'grow', text: item.name }),
        c.searchText ? h('span', { class: 'dim', text: (lib().collectionOf(item.id)?.name ?? '').replace(/^Factory · /, '') }) : null,
        h('span', { class: 'dim', style: { width: '40px', textAlign: 'right' }, text: (item.fileExtension ?? (item.relativePath ?? item.absolutePath ?? 'wav').split('.').pop()).toUpperCase() }),
        h('span', { class: 'dim', style: { width: '60px', textAlign: 'right' }, text: `${(item.sampleRate / 1000).toFixed(1)} kHz` }),
        h('span', { class: 'dim', style: { width: '46px', textAlign: 'right' }, text: item.channels === 1 ? 'Mono' : 'Stereo' }),
        h('span', { style: { width: '60px', textAlign: 'right' }, text: `${item.duration.toFixed(2)} s` }));
      li.addEventListener('click', () => { c.selectedItem = item.id; c.libraryRevision++; if (c.prefs.autoPreview) c.preview(item); c.changed(); });
      li.addEventListener('dblclick', () => c.loadLibraryItem(item));
      li.addEventListener('dragstart', (e) => { e.dataTransfer.setData('application/x-nexora-item', item.id); e.dataTransfer.effectAllowed = 'copy'; });
      li.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        const isUser = !item.url;
        contextMenu(e.clientX, e.clientY, [
          { label: 'Vorhören', action: () => c.preview(item) },
          { label: 'Auf ausgewähltes Pad laden', action: () => c.loadLibraryItem(item) },
          ...(isUser ? [
            { label: 'Umbenennen …', action: () => renameItem(c, item) },
            { label: 'Im Explorer zeigen', action: () => { const loc = lib().location(item); if (loc?.path) import('../core/bridge.js').then(({ bridge }) => bridge.showInFolder(loc.path)); } },
            '-', { label: 'Entfernen', action: async () => { await lib().removeItem(item.id); c.libraryRevision++; c.changed(); } }] : [])
        ]);
      });
      return li;
    });
  });
  const search = h('input', { class: 'ui-input', placeholder: 'Alle Bibliotheken durchsuchen', style: { width: '200px' } });
  search.addEventListener('input', () => { c.searchText = search.value; c.libraryRevision++; c.changed(); });
  const selItem = () => c.selectedItem && lib().item(c.selectedItem);
  const loadBtn = btn('Auf Pad laden', () => { const i = selItem(); if (i) c.loadLibraryItem(i); });
  onUpdate(() => setText(loadBtn, `Auf Pad ${c.selectedPad + 1} laden`));
  const isFactorySel = () => lib().collection(c.selectedCollection)?.isFactory ?? true;
  const renameCol = btn('Umbenennen', async () => {
    const col = lib().collection(c.selectedCollection);
    if (!col || col.isFactory) return;
    const n = await promptText(c, 'Bibliothek umbenennen', col.name);
    if (n) { await lib().renameCollection(col.id, n); c.libraryRevision++; c.changed(); }
  });
  const delCol = btn('Löschen', async () => {
    const col = lib().collection(c.selectedCollection);
    if (!col || col.isFactory) return;
    await lib().removeCollection(col.id); c.selectedCollection = lib().userCollections[0].id; c.libraryRevision++; c.changed();
  }, { danger: true });
  onUpdate(() => { renameCol.disabled = isFactorySel(); delCol.disabled = isFactorySel(); });
  return h('div', { style: { display: 'flex', gap: '14px', width: '100%' } },
    h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } },
      h('span', { class: 'muted', style: { font: '700 8px var(--font)', letterSpacing: '1.2px' }, text: 'BIBLIOTHEKEN' }),
      collections,
      h('div', { class: 'row', style: { width: '210px', flexWrap: 'nowrap' } }, newName,
        btn('+', async () => { if (!newName.value.trim()) return; const col = await lib().createCollection(newName.value.trim()); newName.value = ''; c.selectedCollection = col.id; c.libraryRevision++; c.changed(); })),
      h('div', { class: 'row' }, renameCol, delCol)),
    h('div', { style: { flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' } },
      h('div', { class: 'row' }, search, btn('Importieren …', () => c.importWithDialog(), { tip: 'Audiodateien in die ausgewählte Bibliothek importieren (Strg+I)' }),
        loadBtn, btn('Vorhören', () => { const i = selItem(); if (i) c.preview(i); }), btn('Stopp', () => c.stopPreview()),
        h('span', { style: { flex: 1 } }), h('span', { class: 'muted', text: 'Einträge auf ein Pad ziehen, Doppelklick lädt auf das ausgewählte Pad' })),
      items));
}

async function renameItem(c, item) {
  const n = await promptText(c, 'Sample umbenennen', item.name);
  if (n) { await c.library.renameItem(item.id, n); c.libraryRevision++; c.changed(); }
}

/** Einfache Texteingabe als Dialog (Electron unterstützt window.prompt nicht). */
export function promptText(c, title, value = '') {
  return new Promise((resolve) => {
    const input = h('input', { class: 'ui-input', style: { width: '100%' }, value });
    const close = (v) => { back.remove(); resolve(v); };
    const back = h('div', { class: 'modal-backdrop' }, h('div', { class: 'modal' }, h('h2', { text: title }), input,
      h('div', { class: 'actions' }, h('button', { class: 'ui-btn', text: 'Abbrechen', onclick: () => close(null) }),
        h('button', { class: 'ui-btn primary', text: 'OK', onclick: () => close(input.value.trim() || null) }))));
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') close(input.value.trim() || null); if (e.key === 'Escape') close(null); });
    document.body.append(back);
    input.focus(); input.select();
  });
}

// ------------------------------------------------------------ Master-FX

function effects(c) {
  const m = () => c.project.master;
  const upd = (fn) => c.updateMaster(fn);
  const sync = h('select', { class: 'ui-select', style: { width: '110px' } }, ...Object.entries(TEMPO_DIVISION_NAMES).map(([k, v]) => h('option', { value: k, text: `Sync: ${v}` })));
  sync.addEventListener('change', () => upd((x) => { x.delaySync = sync.value; }));
  onUpdate(() => { if (sync.value !== m().delaySync) sync.value = m().delaySync; });
  const gr = h('span', { style: { font: '500 9px var(--mono)', color: 'var(--turquoise)', height: '20px' } });
  onUpdate(() => setText(gr, `GR ${c.meters.gainReduction.toFixed(0)} dB`));
  const name = h('input', { class: 'ui-input', placeholder: 'Name', style: { width: '130px' } });
  const presetSel = h('select', { class: 'ui-select', style: { width: '130px' } });
  keyedList(presetSel, () => `${c.presetRevision}`, () => {
    c.presets.list('effects').then((list) => {
      presetSel.replaceChildren(h('option', { value: '', text: 'FX-Preset laden …' }), ...list.map((p) => h('option', { value: p.path, text: p.name })));
      presetSel.__list = list;
    });
    return [h('option', { value: '', text: 'FX-Preset laden …' })];
  });
  presetSel.addEventListener('change', () => { const info = presetSel.__list?.find((p) => p.path === presetSel.value); if (info) c.loadEffectPreset(info); presetSel.value = ''; });
  const row = (...k) => h('div', { class: 'row', style: { gap: '2px', flexWrap: 'nowrap', alignItems: 'flex-start' } }, ...k);
  return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } },
    h('div', { class: 'row', style: { gap: '18px', alignItems: 'flex-start', flexWrap: 'nowrap' } },
      dsec('Filter', segment(Object.entries(FILTER_NAMES), () => m().filterMode, (v) => upd((x) => { x.filterMode = v; })),
        row(dk(c, 'masterFilterCutoff', 'CUTOFF'), dk(c, 'masterFilterResonance'))),
      dsec('Drive · Bitcrusher', row(dk(c, 'masterDrive'), dk(c, 'masterCrushBits'), dk(c, 'masterCrushRate', 'RATE'))),
      dsec('Modulation (LFO)', segment(Object.entries(MOD_TARGET_NAMES), () => m().modTarget, (v) => upd((x) => { x.modTarget = v; })),
        row(dk(c, 'modRate', 'RATE'), dk(c, 'modDepth', 'DEPTH'),
          segment(Object.entries(LFO_SHAPE_NAMES).slice(0, 4), () => m().modShape, (v) => upd((x) => { x.modShape = v; })))),
      dsec('EQ', row(dk(c, 'eqLow'), dk(c, 'eqMid'), dk(c, 'eqMidFrequency', 'FREQ'), dk(c, 'eqHigh')))),
    h('div', { class: 'row', style: { gap: '18px', alignItems: 'flex-start', flexWrap: 'nowrap' } },
      dsec('Delay', h('div', { class: 'row' }, sync, check('Ping-Pong', () => m().delayPingPong, (v) => upd((x) => { x.delayPingPong = v; }))),
        row(dk(c, 'delayMix', 'MIX'), dk(c, 'delayTime'), dk(c, 'delayFeedback'), dk(c, 'delayDamping', 'TONE'))),
      dsec('Reverb', h('div', { style: { height: '22px' } }), row(dk(c, 'reverbMix', 'MIX'), dk(c, 'reverbSize'), dk(c, 'reverbDamping'), dk(c, 'reverbWidth'))),
      dsec('Compressor', gr, row(dk(c, 'compThreshold', 'THRESH'), dk(c, 'compRatio'), dk(c, 'compAttack', 'ATTACK'), dk(c, 'compRelease', 'RELEASE'), dk(c, 'compMakeup'))),
      dsec('Preset', name, h('div', { class: 'row' }, btn('Speichern', () => { c.saveEffectPreset(name.value); name.value = ''; }), presetSel),
        btn('FX zurücksetzen', () => upd((x) => Object.assign(x, defaultMaster()))))));
}

// ------------------------------------------------------------ Kits

function kits(c) {
  const list = h('div', { class: 'list', style: { width: '380px', height: '210px' } });
  let selected = null;
  let items = [];
  keyedList(list, () => `${c.presetRevision}|${selected}`, () => {
    c.presets.list('kit').then((l) => {
      items = l;
      list.replaceChildren(...(l.length ? l.map((info) => {
        const li = h('div', { class: `li ${selected === info.path ? 'sel' : ''}`, onclick: () => { selected = info.path; c.presetRevision++; c.changed(); } },
          h('span', { text: '▦', style: { color: 'var(--pink)' } }), h('span', { class: 'grow', text: info.name }));
        li.addEventListener('dblclick', () => c.loadKit(info));
        return li;
      }) : [h('div', { class: 'sechead', style: { padding: '16px' }, text: 'Noch keine eigenen Kits gespeichert.' })]));
    });
    return [];
  });
  const kitName = h('input', { class: 'ui-input', placeholder: 'Kit-Name', style: { width: '180px' } });
  const curTitle = () => `AKTUELLES KIT: ${c.project.kitName}`;
  const factoryButton = (name, action) => {
    const b = h('button', { class: 'fbtn', style: { width: '118px', height: '24px', justifyContent: 'flex-start', paddingLeft: '8px' }, title: `Werks-Kit „${name}“ laden (Patterns bleiben erhalten)`, onclick: action },
      h('span', { text: '▦ ', style: { color: 'var(--pink)' } }), name);
    onUpdate(() => setStyle(b, 'box-shadow', c.project.kitName === name ? 'inset 0 0 0 1px var(--turquoise)' : ''));
    return b;
  };
  const factoryKits = c.library.factory?.kits ?? [];
  return h('div', { style: { display: 'flex', gap: '18px' } },
    h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } },
      h('span', { class: 'muted', style: { font: '700 8px var(--font)', letterSpacing: '1.2px' }, text: 'GESPEICHERTE KITS' }), list,
      h('div', { class: 'row' },
        btn('Laden', () => { const info = items.find((i) => i.path === selected); if (info) c.loadKit(info); }),
        btn('Löschen', () => { const info = items.find((i) => i.path === selected); if (info) { c.deletePreset(info); selected = null; } }, { danger: true }))),
    h('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px' } },
      dsec(curTitle, h('div', { class: 'row' }, kitName, btn('Als Kit speichern', () => { c.saveKit(kitName.value); kitName.value = ''; })),
        h('span', { class: 'muted', style: { width: '340px' }, text: 'Ein Kit enthält alle 16 Pad-Belegungen mit Kopien der Samples, Namen, Tasten und Pad-Einstellungen.' })),
      dsec('Werks-Kits', h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(4, 118px)', gap: '6px' } },
        factoryButton(c.library.factory?.classicKitName ?? 'NEXORA Factory', () => c.loadClassicKit(false)),
        ...factoryKits.map((k) => factoryButton(k.name, () => c.loadFactoryKit(k)))),
        h('div', { class: 'row' }, btn('Factory + Demo-Patterns', () => c.loadClassicKit(true)), btn('Alle Pads leeren', () => c.clearAllPads(), { danger: true }), btn('Neues leeres Projekt', () => c.newProject('empty'), { tip: 'Leere Pads und leere Patterns (Strg+Umschalt+N)' }))),
      dsec('Presets-Ordner', h('div', { class: 'row' }, btn('Im Explorer zeigen', () => import('../core/bridge.js').then(({ bridge }) => bridge.openPath(c.presets.root))),
        h('span', { class: 'muted', style: { font: '9px var(--mono)' }, text: c.presets.root })))));
}

// ------------------------------------------------------------ MIDI

function midiPanel(c) {
  const midi = () => c.project.midi;
  const devices = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '4px' } });
  keyedList(devices, () => c.midiNames.join('|') + (c.midi?.error ?? ''), () =>
    c.midiNames.length ? c.midiNames.map((n) => h('div', { class: 'row' }, h('i', { class: 'led on', style: { '--led-color': 'var(--turquoise)' } }), n))
      : [h('span', { class: 'muted', text: c.midi?.error ?? 'Kein MIDI-Gerät angeschlossen' })]);
  const channel = h('select', { class: 'ui-select', style: { width: '200px' } }, h('option', { value: 0, text: 'Kanal: Omni' }),
    ...Array.from({ length: 16 }, (_, i) => h('option', { value: i + 1, text: `Kanal ${i + 1}` })));
  channel.addEventListener('change', () => { midi().inputChannel = Number(channel.value); c.markDirty(); });
  onUpdate(() => { if (channel.value !== String(midi().inputChannel)) channel.value = String(midi().inputChannel); });

  const notes = h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(4, 118px)', gap: '4px' } });
  for (let p = 0; p < 16; p++) {
    const label = h('span', { style: { font: '500 9px var(--mono)', width: '66px' } });
    const cell = h('div', { class: 'row', style: { padding: '3px', borderRadius: '3px', background: 'var(--panel)', flexWrap: 'nowrap', gap: '3px' }, title: 'Doppelklick: Note per MIDI lernen' },
      h('span', { text: pad2(p + 1), style: { color: 'var(--turquoise)' } }),
      h('button', { class: 'tog', text: '–', onclick: () => c.assignNote(Math.max(0, midi().padNotes[p] - 1), p) }), label,
      h('button', { class: 'tog', text: '+', onclick: () => c.assignNote(Math.min(127, Math.max(0, midi().padNotes[p]) + 1), p) }));
    cell.addEventListener('dblclick', () => { c.noteLearnPad = p; c.changed(); });
    onUpdate(() => { setText(label, noteName(midi().padNotes[p])); setStyle(cell, 'background', c.noteLearnPad === p ? 'color-mix(in srgb, var(--pink) 40%, transparent)' : 'var(--panel)'); });
    notes.append(cell);
  }
  const learn = btn('MIDI-Learn starten', () => c.toggleMIDILearn());
  const learnInfo = h('span', { style: { color: 'var(--pink)' } });
  onUpdate(() => { setText(learn, c.midiLearnActive ? 'Learn beenden' : 'MIDI-Learn starten'); setText(learnInfo, c.midiLearnActive ? (c.learnTarget ? `Ziel: ${PARAMS[c.learnTarget].name} – Controller bewegen` : 'Regler anklicken …') : ''); });
  const mappings = h('div', { class: 'list', style: { width: '320px', height: '200px', padding: '4px' } });
  keyedList(mappings, () => JSON.stringify(midi().ccMappings), () => midi().ccMappings.length
    ? midi().ccMappings.map((m) => h('div', { class: 'li' }, h('span', { style: { width: '50px' }, text: `CC ${m.controller}` }), h('span', { style: { width: '40px' }, text: m.channel === 0 ? 'Alle' : `Ch ${m.channel}` }),
      h('span', { class: 'grow', text: PARAMS[m.parameter]?.name ?? m.parameter }), h('button', { class: 'tog', text: '×', onclick: () => c.removeMapping(m.id) })))
    : [h('div', { class: 'sechead', text: 'Noch keine Zuordnungen. MIDI-Learn starten, einen Regler anklicken und am Gerät einen Controller bewegen.' })]);
  return h('div', { style: { display: 'flex', gap: '18px' } },
    h('div', { style: { width: '250px', display: 'flex', flexDirection: 'column', gap: '8px' } },
      dsec('Eingänge', devices, btn('Geräte neu suchen', () => c.midi?.connect())),
      dsec('Einstellungen', channel,
        check('Start/Stop von MIDI übernehmen', () => midi().respondToTransport, (v) => { midi().respondToTransport = v; c.markDirty(); }),
        check('Feste Anschlagstärke', () => midi().fixedVelocity, (v) => { midi().fixedVelocity = v; c.markDirty(); }))),
    dsec('Pad-Noten', notes, btn('Standard (C1–D#2)', () => { midi().padNotes = Array.from({ length: 16 }, (_, i) => 36 + i); c.markDirty(); c.changed(); })),
    dsec('CC-Zuordnungen', h('div', { class: 'row' }, learn, learnInfo), mappings));
}
