// Das Gehäuse des Instruments (gleiche Anordnung wie in der Mac-Version).
import { h, setText, setClass, setStyle, onUpdate, faceButton, led, pad2, contextMenu } from './dom.js';
import { paramKnob } from './knob.js';
import { PARAMS, slotName, toNormalized } from '../engine/model.js';
import { keyboardSemitone, cycle, LFO_TARGET_NAMES, LFO_SHAPE_NAMES, FILTER_NAMES } from '../core/controller.js';

const XY_PARAMS = ['masterFilterCutoff', 'masterFilterResonance', 'reverbMix', 'reverbSize', 'delayMix', 'delayFeedback', 'delayTime',
  'masterDrive', 'masterCrushBits', 'masterCrushRate', 'modRate', 'modDepth', 'eqLow', 'eqHigh', 'compThreshold', 'masterVolume',
  'padPitch', 'padCutoff', 'padResonance', 'padStart', 'padDecay', 'padPan', 'padLFORate', 'padLFODepth', 'swing'];
const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

export function buildBody(c) {
  return h('div', { class: 'body' },
    h('div', { class: 'body-inner' },
      leftColumn(c),
      h('div', { class: 'right-col' }, brand(c), sections(c), buttonRow(c), pads(c))));
}

// ------------------------------------------------------------ Linke Spalte

function leftColumn(c) {
  const meter = (side) => {
    const el = h('div', { class: 'meter' });
    const segs = Array.from({ length: 10 }, (_, i) => {
      const s = h('i', { style: { background: i >= 8 ? 'var(--pink)' : i >= 6 ? '#ffd166' : 'var(--turquoise)' } });
      el.append(s);
      return s;
    });
    onUpdate(() => {
      const lvl = side === 'L' ? c.meters.peakL : c.meters.peakR;
      const db = lvl > 1e-5 ? 20 * Math.log10(lvl) : -100;
      const lit = Math.round(Math.max(0, Math.min(1, (db + 48) / 48)) * 10);
      segs.forEach((s, i) => setClass(s, 'on', i < lit));
    });
    return el;
  };
  const top = h('div', { class: 'row', style: { height: '72px', alignItems: 'flex-start', gap: '18px' } },
    paramKnob(c, 'masterVolume', { title: 'Volume', size: 36, showValue: false }),
    paramKnob(c, 'swing', { title: 'Swing', size: 36, showValue: false }),
    h('div', { style: { flex: 1 } }),
    h('div', { class: 'meters', style: { marginTop: '6px' }, title: 'Ausgangspegel links/rechts' }, meter('L'), meter('R')));

  const transport = h('div', { class: 'row', style: { gap: '10px' } },
    faceButton({ icon: 'record', width: 64, height: 50, tip: 'Live-Aufnahme (Strg+R)', onClick: () => c.toggleRecord(), lit: () => c.isRecording, litColor: 'var(--led-red)' }),
    faceButton({ icon: 'stop', width: 64, height: 50, tip: 'Stopp – zurück zum Anfang', onClick: () => c.stop() }),
    faceButton({ icon: 'playpause', width: 64, height: 50, tip: 'Play/Pause (Leertaste = Play/Stop)', onClick: () => c.playPause(), lit: () => c.meters.transport === 'playing', litColor: 'var(--play-blue)', fill: true }),
    faceButton({ title: 'Tap', width: 64, height: 50, font: 15, tip: 'Tap-Tempo (Strg+T)', onClick: () => c.tapTempo() }));

  const fn = h('div', { class: 'row', style: { gap: '10px' } },
    faceButton({ title: 'Click', width: 64, height: 26, tip: 'Metronom (Strg+K)', onClick: () => c.toggleMetronome(), lit: () => c.project.sequencer.metronome }),
    faceButton({ title: 'XY Latch', width: 64, height: 26, tip: 'Touchpad-Werte nach dem Loslassen halten', onClick: () => { c.xyLatch = !c.xyLatch; c.changed(); }, lit: () => c.xyLatch }),
    faceButton({ title: 'Master Fx', width: 64, height: 26, tip: 'Master-Effekte: Delay, Hall, EQ, Kompressor, Modulation', onClick: () => c.toggleDrawer('effects'), lit: () => c.drawer === 'effects' }),
    faceButton({ title: 'Learn', width: 64, height: 26, tip: 'MIDI-Learn: Regler anklicken, dann Controller bewegen', onClick: () => c.toggleMIDILearn(), lit: () => c.midiLearnActive, litColor: 'var(--turquoise)' }));

  return h('div', { class: 'left-col' }, top, lcd(c), transport, fn, xyPad(c));
}

// ------------------------------------------------------------ LCD

function lcd(c) {
  const mode = h('span'), bpm = h('span', { class: 'bpm' }), ptn = h('span', { class: 'ptn' });
  const small = h('div', { class: 'small' }), big = h('div', { class: 'big' });
  const wave = h('canvas', { class: 'wave', width: 548, height: 36 });
  const steps = h('div', { class: 'steps' });
  const stepEls = Array.from({ length: 16 }, () => { const i = h('i'); steps.append(i); return i; });
  const info = h('span'), sampleInfo = h('span'), voices = h('span');
  let lastWaveKey = '';
  onUpdate(() => {
    const pad = c.selectedPad, cfg = c.project.pads[pad], s = c.padSamples[pad], m = c.meters;
    setText(mode, c.midiLearnActive ? 'LEARN' : c.isRecording ? '● REC' : c.padMode === 'step' ? 'SEQ' : c.padMode === 'keyboard' ? 'KEYS'
      : c.drawer ? c.drawer.toUpperCase().slice(0, 8) : 'TRIGGER');
    setText(bpm, c.project.bpm.toFixed(1));
    setText(ptn, `PTN ${slotName(c.project.sequencer.currentPattern)}${m.queuedPattern >= 0 ? '›' + slotName(m.queuedPattern) : ''}`);
    if (c.lcd) { setText(small, c.lcd.title); setText(big, c.lcd.value || ' '); setStyle(big, 'font-size', c.lcd.value.length > 16 ? '15px' : '19px'); }
    else { setText(small, String(pad + 1).padStart(3, '0')); setText(big, s ? cfg.name.charAt(0) + cfg.name.slice(1).toLowerCase() : '— empty —'); setStyle(big, 'font-size', '21px'); }
    const pattern = c.currentPattern;
    const playing = m.transport !== 'stopped';
    const offset = c.stepPage * 16;
    stepEls.forEach((el, j) => {
      const i = offset + j;
      const on = pattern.steps[pad][i].active;
      setStyle(el, 'opacity', i >= pattern.length ? '0.06' : playing && m.currentStep === i ? '1' : on ? '0.6' : '0.15');
    });
    const song = c.project.sequencer.songMode && m.songIndex >= 0 ? ` SONG ${m.songIndex + 1}/${c.project.patternChain.length}` : '';
    const pages = c.pageCount > 1 ? ` P${c.stepPage + 1}/${c.pageCount}` : '';
    setText(info, `Pad:${pad2(pad + 1)} ${({ oneShot: 'ONE', gate: 'GATE', loop: 'LOOP' })[cfg.settings.playMode]}${pages}${song}`);
    setText(sampleInfo, s ? `${(s.sampleRate / 1000).toFixed(1)}k ${s.stereo ? 'ST' : 'MO'} ${(s.frameCount / s.sampleRate).toFixed(2)}s` : '');
    setText(voices, `V${m.activeVoices}`);
    const key = `${pad}|${cfg.settings.start}|${cfg.settings.end}|${c.padWaveforms[pad] ? c.padWaveforms[pad].length + ':' + c.padWaveforms[pad][10] : 'x'}|${document.body.className}`;
    if (key !== lastWaveKey) { lastWaveKey = key; drawWave(wave, c.padWaveforms[pad], cfg.settings, true); }
  });
  return h('div', { class: 'lcd', title: 'Display: Tempo, Pattern, ausgewähltes Pad, Sample-Informationen und Modus' },
    h('div', { class: 'screen' },
      h('div', { class: 'top' }, mode, bpm, ptn),
      h('div', { class: 'band' }, small, big),
      wave, steps,
      h('div', { class: 'bottom' }, info, sampleInfo, h('span', { class: 'grow' }), voices)));
}

/** Zeichnet eine Wellenform mit Start-/Endmarkern. */
export function drawWave(canvas, peaks, settings, lcdStyle) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height, mid = H / 2;
  const css = getComputedStyle(document.body);
  const ink = lcdStyle ? css.getPropertyValue('--lcd-ink').trim() : css.getPropertyValue('--turquoise').trim();
  ctx.clearRect(0, 0, W, H);
  if (!peaks) { ctx.fillStyle = ink; ctx.globalAlpha = 0.2; ctx.fillRect(0, mid, W, 1); ctx.globalAlpha = 1; return; }
  const bw = W / peaks.length;
  for (let i = 0; i < peaks.length; i++) {
    const pos = i / peaks.length;
    const inside = pos >= settings.start && pos <= settings.end;
    const hgt = Math.max(1, Math.min(1, peaks[i]) * H * 0.48);
    ctx.globalAlpha = inside ? (lcdStyle ? 0.85 : 1) : 0.22;
    ctx.fillStyle = ink;
    ctx.fillRect(i * bw, mid - hgt, Math.max(bw - 0.5, 0.6), hgt * 2);
  }
  ctx.globalAlpha = 1;
  const marker = lcdStyle ? ink : css.getPropertyValue('--pink').trim();
  for (const [p, isStart] of [[settings.start, true], [settings.end, false]]) {
    const x = p * W;
    ctx.fillStyle = marker;
    ctx.fillRect(x - 0.75, 0, 1.5, H);
    ctx.fillRect(isStart ? x : x - 6, 0, 6, 6);
  }
  if (settings.reverse) { ctx.fillStyle = marker; ctx.font = `bold ${Math.round(H / 4)}px monospace`; ctx.fillText('◀ REV', W - 60, H - 6); }
}

// ------------------------------------------------------------ Touchpad

function xyPad(c) {
  const mkSelect = (axis) => {
    const sel = h('select', { title: `${axis.toUpperCase()}-Achse des Touchpads` },
      ...XY_PARAMS.map((id) => h('option', { value: id, text: `${axis.toUpperCase()}: ${PARAMS[id].short}` })));
    sel.addEventListener('change', () => c.assignXY(axis, sel.value));
    onUpdate(() => { const v = c.project.xyPad[axis === 'x' ? 'xParameter' : 'yParameter']; if (sel.value !== v) sel.value = v; });
    return sel;
  };
  const dot = h('div', { class: 'dot' }), cx = h('div', { class: 'cross-x' }), cy = h('div', { class: 'cross-y' });
  const xl = h('div', { class: 'xl' }), yl = h('div', { class: 'yl' });
  const pad = h('div', { class: 'xy', title: 'Touchpad: mit Maus oder Touchpad ziehen. Achsen oben auswählen oder per Rechtsklick auf einen Regler zuweisen.' }, cx, cy, dot, xl, yl);
  let restore = null;
  const move = (e) => {
    const r = pad.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    const y = Math.min(1, Math.max(0, 1 - (e.clientY - r.top) / r.height));
    c.setXY(x, y);
  };
  pad.addEventListener('pointerdown', (e) => {
    pad.setPointerCapture(e.pointerId);
    restore = [c.normalized(c.project.xyPad.xParameter), c.normalized(c.project.xyPad.yParameter)];
    pad.classList.add('touching');
    move(e);
  });
  pad.addEventListener('pointermove', (e) => { if (pad.classList.contains('touching')) move(e); });
  const up = () => {
    if (!pad.classList.contains('touching')) return;
    pad.classList.remove('touching');
    if (!c.xyLatch && restore) c.setXY(restore[0], restore[1]);
    restore = null;
  };
  pad.addEventListener('pointerup', up);
  pad.addEventListener('pointercancel', up);
  onUpdate(() => {
    const xp = c.project.xyPad.xParameter, yp = c.project.xyPad.yParameter;
    const x = c.normalized(xp), y = c.normalized(yp);
    setStyle(dot, 'left', `${(x * 100).toFixed(2)}%`); setStyle(dot, 'top', `${((1 - y) * 100).toFixed(2)}%`);
    setStyle(cx, 'left', `${(x * 100).toFixed(2)}%`); setStyle(cy, 'top', `${((1 - y) * 100).toFixed(2)}%`);
    setText(xl, `X ${c.display(xp)}`); setText(yl, `Y ${c.display(yp)}`);
  });
  return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px' } },
    h('div', { class: 'xy-head' }, mkSelect('x'), mkSelect('y'), h('div', { style: { flex: 1 } }), h('span', { class: 'label caps muted', text: 'Touch Pad' })),
    pad);
}

// ------------------------------------------------------------ Kopfzeile

function brand(c) {
  return h('div', { class: 'brand' },
    h('div', { class: 'leds' },
      led('var(--turquoise)', () => performance.now() < c.meters.midiActivityUntil), h('span', { class: 'label caps', text: 'MIDI' }),
      led('var(--led-red)', () => c.isRecording), h('span', { class: 'label caps', text: 'REC' }),
      led('var(--blue-glow)', () => c.meters.transport === 'playing'), h('span', { class: 'label caps', text: 'RUN' })),
    h('div', { class: 'logo' },
      h('div', { class: 'name' }, h('b', { text: 'nexora' }), ' ', h('span', { text: 'sampler' })),
      h('div', { class: 'sub', text: 'PERFORMANCE SAMPLER · 16 PADS' })));
}

// ------------------------------------------------------------ Regler-Sektionen

function sections(c) {
  const sel = () => c.project.pads[c.selectedPad];
  const upd = (fn) => c.updatePad(c.selectedPad, fn);
  const section = (title, width, big, row2, row3) => h('div', { class: 'section', style: { width: `${width}px` } },
    h('div', { class: 'stitle', text: title }), h('div', { class: 'big' }, ...big), h('div', { class: 'row2' }, ...row2), h('div', { class: 'row3' }, ...row3));
  const filterBtn = (title, mode) => faceButton({ title, width: 50, height: 26, tip: `Pad-Filter ${title} – erneut drücken schaltet aus`,
    lit: () => sel().settings.filterMode === mode,
    onClick: () => { upd((p) => { p.settings.filterMode = p.settings.filterMode === mode ? 'off' : mode; }); c.showLCD('FILTER', FILTER_NAMES[sel().settings.filterMode]); } });

  const nav = h('div', { class: 'nav' },
    h('div', { style: { paddingTop: '22px', width: '140px' } }, paramKnob(c, 'tempo', { title: 'Tempo', size: 66, style: 'jog' })),
    h('div', { class: 'pair' },
      faceButton({ icon: 'left', width: 58, height: 24, tip: 'Vorheriges Pattern', onClick: () => c.stepPattern(-1) }),
      faceButton({ icon: 'right', width: 58, height: 24, tip: 'Nächstes Pattern', onClick: () => c.stepPattern(1) })),
    h('div', { class: 'pair' },
      faceButton({ title: 'Edit', width: 58, height: 24, tip: 'Pad-Editor', onClick: () => c.toggleDrawer('editor'), lit: () => c.drawer === 'editor' }),
      faceButton({ title: 'Exit', width: 58, height: 24, tip: 'Bereich schließen / Modus verlassen', onClick: () => c.exitAction() })),
    h('div', { class: 'pair' },
      faceButton({ title: 'Browse', width: 58, height: 24, tip: 'Sample-Browser', onClick: () => c.toggleDrawer('browser'), lit: () => c.drawer === 'browser' }),
      faceButton({ title: 'Kit', width: 58, height: 24, tip: 'Kits & Presets', onClick: () => c.toggleDrawer('kits'), lit: () => c.drawer === 'kits' })));

  return h('div', { class: 'sections' },
    nav,
    section('Sample', 130,
      [paramKnob(c, 'padStart', { title: '', size: 60 })],
      [paramKnob(c, 'padPitch', { title: 'Pitch' })],
      [paramKnob(c, 'padEnd', { title: 'End' })]),
    section('Filter', 180,
      [paramKnob(c, 'padCutoff', { title: '', size: 60 })],
      [paramKnob(c, 'padResonance', { title: 'Resonance' }), paramKnob(c, 'padFilterEnv', { title: 'EG Int' })],
      [h('div', { class: 'row', style: { marginTop: '14px' } }, filterBtn('LPF', 'lowPass'), filterBtn('HPF', 'highPass'), filterBtn('BPF', 'bandPass'))]),
    section('Modulation', 140,
      [paramKnob(c, 'padLFODepth', { title: '', size: 60 })],
      [paramKnob(c, 'padLFORate', { title: 'Speed' })],
      [h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' } },
        faceButton({ width: 82, height: 24, tip: 'Modulationsziel: Vibrato, Tremolo, Filter, Auto-Pan oder aus', lit: () => sel().settings.lfoTarget !== 'off',
          title: ' ', dynamicTitle: () => sel().settings.lfoTarget === 'off' ? 'Mod Off' : `→ ${LFO_TARGET_NAMES[sel().settings.lfoTarget]}`,
          onClick: () => { upd((p) => { p.settings.lfoTarget = cycle(['off', 'pitch', 'volume', 'cutoff', 'pan'], p.settings.lfoTarget); }); c.showLCD('MOD TARGET', LFO_TARGET_NAMES[sel().settings.lfoTarget]); } }),
        faceButton({ width: 82, height: 24, tip: 'LFO-Wellenform', title: ' ', dynamicTitle: () => `Wave ${LFO_SHAPE_NAMES[sel().settings.lfoShape]}`,
          onClick: () => { upd((p) => { p.settings.lfoShape = cycle(['sine', 'triangle', 'square', 'sawUp', 'sawDown', 'sampleHold'], p.settings.lfoShape); }); c.showLCD('LFO WAVE', LFO_SHAPE_NAMES[sel().settings.lfoShape]); } }))]),
    section('Amp/EG', 190,
      [paramKnob(c, 'padVolume', { title: 'Level', size: 44 }), paramKnob(c, 'padPan', { title: 'Pan', size: 44 })],
      [h('div', { class: 'row', style: { gap: '16px', flexWrap: 'nowrap' } }, paramKnob(c, 'padAttack', { title: 'Attack' }), paramKnob(c, 'padDecay', { title: 'Decay' }), paramKnob(c, 'padRelease', { title: 'Release' }))],
      [h('div', { class: 'row', style: { marginTop: '14px', gap: '8px' } },
        faceButton({ title: 'MFX Send', width: 80, height: 26, tip: 'Send des Pads zu Hall und Delay ein/aus', lit: () => sel().settings.reverbSend > 0 || sel().settings.delaySend > 0,
          onClick: () => upd((p) => { const on = p.settings.reverbSend > 0 || p.settings.delaySend > 0; p.settings.reverbSend = on ? 0 : 1; p.settings.delaySend = on ? 0 : 1; }) }),
        faceButton({ width: 80, height: 26, title: ' ', tip: 'Wiedergabe: One-Shot, Amp EG (Gate) oder Loop', lit: () => sel().settings.playMode !== 'oneShot',
          dynamicTitle: () => ({ oneShot: 'One Shot', gate: 'Amp EG', loop: 'Loop' })[sel().settings.playMode],
          onClick: () => upd((p) => { p.settings.playMode = cycle(['oneShot', 'gate', 'loop'], p.settings.playMode); }) }))]),
    section('Insert Fx', 134,
      [paramKnob(c, 'padDrive', { title: '', size: 60 })],
      [paramKnob(c, 'padCrushBits', { title: 'Edit' })],
      [h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' } },
        faceButton({ title: 'IFX On', width: 72, height: 24, tip: 'Insert-Effekte (Drive, Bitcrusher) ein/aus', lit: () => sel().settings.insertFXOn, onClick: () => upd((p) => { p.settings.insertFXOn = !p.settings.insertFXOn; }) }),
        faceButton({ width: 72, height: 24, title: ' ', dynamicTitle: () => sel().settings.reverse ? '◀ Reverse' : 'Reverse', tip: 'Sample rückwärts abspielen',
          lit: () => sel().settings.reverse, onClick: () => upd((p) => { p.settings.reverse = !p.settings.reverse; }) }))]));
}

// ------------------------------------------------------------ Tastenreihe

function buttonRow(c) {
  const b = (title, tip, onClick, lit) => faceButton({ title, width: 74, height: 28, tip, onClick, lit });
  const row = h('div', { class: 'btn-row' },
    b('◀ Pad', 'Vorheriges Pad auswählen', () => c.selectPad(c.selectedPad - 1)),
    b('Pad ▶', 'Nächstes Pad auswählen', () => c.selectPad(c.selectedPad + 1)),
    b('Pad Mute', 'Spur des ausgewählten Pads stummschalten', () => c.toggleMute(c.selectedPad), () => c.project.sequencer.trackMutes[c.selectedPad]),
    b('Pad Erase', 'Spur des ausgewählten Pads im Pattern löschen', () => c.clearTrack(c.selectedPad)),
    b('Trigger', 'Pads spielen die Samples', () => c.setPadMode('play'), () => c.padMode === 'play'),
    b('Sequencer', 'Pads = 16 Schritte der ausgewählten Spur', () => c.setPadMode('step'), () => c.padMode === 'step'),
    b('Keyboard', 'Pads spielen das ausgewählte Sample chromatisch', () => c.setPadMode('keyboard'), () => c.padMode === 'keyboard'),
    b('Seq Edit', 'Sequencer-Raster 16 × 16', () => c.toggleDrawer('sequencer'), () => c.drawer === 'sequencer'),
    b('MIDI', 'MIDI-Geräte, Noten und CC-Zuordnungen', () => c.toggleDrawer('midi'), () => c.drawer === 'midi'),
    faceButton({ width: 74, height: 28, title: ' ', dynamicTitle: () => `Bank ${c.patternBank === 0 ? 'A–D' : 'E–H'}`, tip: 'Pattern-Bank umschalten',
      onClick: () => { c.patternBank = 1 - c.patternBank; c.changed(); } }),
    h('div', { class: 'spacer' }));
  for (let i = 0; i < 4; i++) {
    const slot = () => c.patternBank * 4 + i;
    const btn = faceButton({ title: ' ', width: 27, height: 44, font: 12, dynamicTitle: () => slotName(slot()),
      tip: 'Pattern (Strg+1 … Strg+8)', onClick: () => c.selectPattern(slot()),
      lit: () => c.project.sequencer.currentPattern === slot() || c.meters.queuedPattern === slot(),
      litColor: () => (c.meters.queuedPattern === slot() ? 'var(--turquoise)' : 'var(--violet)'),
      fill: () => c.project.sequencer.currentPattern === slot() });
    row.append(btn);
  }
  return row;
}

// ------------------------------------------------------------ Pads

function pads(c) {
  const wrap = h('div', { class: 'pads' });
  for (let r = 0; r < 2; r++) {
    const row = h('div', { class: 'pad-row' });
    for (let col = 0; col < 8; col++) {
      row.append(padView(c, r * 8 + col));
      if (col === 3) row.append(h('div', { class: 'gap' }));
    }
    wrap.append(row);
  }
  return wrap;
}

function padView(c, index) {
  const glow = h('div', { class: 'glow' }), ledEl = h('div', { class: 'ledp' });
  const num = h('div', { class: 'num', text: String(index + 1) }), key = h('div', { class: 'key' }), cap = h('div', { class: 'cap' });
  const spinner = h('div', { class: 'spinner' });
  const el = h('div', { class: 'pad' }, glow, ledEl, num, key, cap, spinner);
  let pressed = false;
  el.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    el.setPointerCapture(e.pointerId);
    pressed = true; el.classList.add('pressed');
    const r = el.getBoundingClientRect();
    const vel = c.prefs.velocityFromPosition ? Math.max(0.25, Math.min(1, 1 - ((e.clientY - r.top) / r.height) * 0.75)) : c.prefs.keyboardVelocity;
    c.padDown(index, vel);
  });
  const up = () => { if (!pressed) return; pressed = false; el.classList.remove('pressed'); c.padUp(index); };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  el.addEventListener('dragover', (e) => { e.preventDefault(); el.classList.add('drop'); });
  el.addEventListener('dragleave', () => el.classList.remove('drop'));
  el.addEventListener('drop', (e) => { e.preventDefault(); el.classList.remove('drop'); c.handleDrop(e.dataTransfer, index); });
  el.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    contextMenu(e.clientX, e.clientY, [
      { label: 'Auswählen', action: () => c.selectPad(index) },
      { label: 'Sample laden …', action: () => { c.selectedPad = index; c.chooseSampleForSelectedPad(); } },
      { label: 'Im Pad-Editor bearbeiten', action: () => { c.selectedPad = index; c.drawer = 'editor'; c.changed(); } },
      { label: 'MIDI-Note lernen', action: () => { c.noteLearnPad = index; c.showLCD(`PAD ${pad2(index + 1)}`, 'PLAY A MIDI NOTE', 3); } },
      '-',
      { label: 'Spur im Pattern löschen', action: () => c.clearTrack(index) },
      { label: 'Pad leeren', action: () => c.clearPad(index) }
    ]);
  });
  onUpdate(() => {
    const cfg = c.project.pads[index];
    const has = !!c.padSamples[index];
    const selected = c.selectedPad === index;
    let color = 'var(--led-red)', intensity = 0, caption;
    if (c.padMode === 'step') {
      const pattern = c.currentPattern;
      const step = c.stepPage * 16 + index;
      const st = pattern.steps[c.selectedPad][step];
      const inRange = step < pattern.length;
      if (c.meters.transport !== 'stopped' && c.meters.currentStep === step) { color = 'var(--violet)'; intensity = 1; }
      else if (st.active && inRange) intensity = 0.45 + 0.55 * st.velocity;
      else intensity = inRange ? 0.05 : 0;
      caption = `STEP ${step + 1}`;
    } else if (c.padMode === 'keyboard') {
      const semi = keyboardSemitone(index);
      if (semi == null) { intensity = 0; caption = ''; }
      else {
        const black = [1, 3, 6, 8, 10].includes(semi % 12);
        color = black ? 'var(--blue-glow)' : '#ffffff';
        intensity = c.keyboardHeld.has(index) ? 1 : 0.35;
        caption = NOTE_NAMES[semi % 12] + (semi >= 12 ? "'" : '');
      }
    } else {
      const g = c.meters.padGlow[index];
      if (selected) { color = 'var(--violet)'; intensity = Math.max(0.75, g); }
      else intensity = Math.max(has ? 0.3 : 0, g);
      caption = has ? cfg.name : 'EMPTY';
    }
    const iv = intensity.toFixed(2);
    if (el.__iv !== iv + color) {
      el.__iv = iv + color;
      setStyle(el, '--led', color);
      glow.style.opacity = (0.55 * intensity).toFixed(2);
      ledEl.style.background = intensity > 0.02 ? color : '#3a2a30';
      ledEl.style.opacity = (0.35 + 0.65 * intensity).toFixed(2);
      ledEl.style.boxShadow = intensity > 0.02 ? `0 0 ${(8 * intensity).toFixed(1)}px ${color}` : 'none';
      ledEl.style.setProperty('--hl', intensity);
    }
    setText(cap, caption);
    setText(key, cfg.keyboardKey);
    setClass(el, 'selected', selected && c.padMode === 'play');
    spinner.style.display = c.loadingPads.has(index) ? 'block' : 'none';
    el.title = `Pad ${index + 1}: ${has ? cfg.name : 'leer'} · Taste ${cfg.keyboardKey.toUpperCase() || '–'}. Audiodatei hierher ziehen zum Laden.`;
  });
  return el;
}

export { toNormalized };
