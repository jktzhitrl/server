// Drehregler: Ziehen (Maus/Touchpad), Mausrad, Doppelklick = Standardwert, Rechtsklick = Menü.
import { h, setText, setClass, setStyle, onUpdate, contextMenu } from './dom.js';
import { PARAMS, fromNormalized, toNormalized } from '../engine/model.js';

const ARC = 'M 17.47 82.53 A 46 46 0 1 1 82.53 82.53';

export function knob({ size = 36, style = 'standard', title = '', showValue = true, get, set, onBegin, reset, menu, tip }) {
  const valueArc = h('path');
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 100 100');
  svg.innerHTML = `<path class="track" d="${ARC}" pathLength="100"/><path class="value" d="${ARC}" pathLength="100" stroke-dasharray="0 100"/>`;
  const rot = h('div', { class: 'rot' }, h('div', { class: 'mark' }));
  const dial = h('div', { class: 'dial', title: tip ?? '' }, svg, h('div', { class: 'skirt' }), h('div', { class: 'cap' }), rot, h('i', { class: 'map-dot' }));
  const titleEl = title ? h('div', { class: 'title', text: title }) : null;
  const valEl = showValue ? h('div', { class: 'val' }) : null;
  const el = h('div', { class: `knob ${style === 'jog' ? 'jog' : ''} ${size > 50 ? 'kbig' : ''}`, style: { '--size': `${size}px` } }, dial, titleEl, valEl);
  el.style.setProperty('--size', `${size}px`);
  const arc = svg.querySelector('.value');

  let drag = null;
  dial.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    dial.setPointerCapture(e.pointerId);
    drag = { x: e.clientX, y: e.clientY, start: get().n };
    onBegin?.();
    e.preventDefault();
  });
  dial.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const fine = e.shiftKey || e.altKey;
    const sens = (fine ? 1000 : 200) * (style === 'jog' ? 2.5 : 1);
    const scale = el.closest('#canvas')?.__scale ?? 1;
    const delta = ((drag.y - e.clientY) + (e.clientX - drag.x)) / scale / sens;
    set(Math.min(1, Math.max(0, drag.start + delta)));
  });
  const end = () => { drag = null; };
  dial.addEventListener('pointerup', end);
  dial.addEventListener('pointercancel', end);
  dial.addEventListener('dblclick', () => reset?.());
  dial.addEventListener('wheel', (e) => {
    e.preventDefault();
    const step = (e.shiftKey ? 0.002 : 0.01) * (style === 'jog' ? 0.5 : 1);
    onBegin?.();
    set(Math.min(1, Math.max(0, get().n - Math.sign(e.deltaY) * step)));
  }, { passive: false });
  if (menu) dial.addEventListener('contextmenu', (e) => { e.preventDefault(); contextMenu(e.clientX, e.clientY, menu()); });

  onUpdate(() => {
    const v = get();
    const n = Math.min(1, Math.max(0, v.n));
    const key = n.toFixed(4);
    if (el.__n !== key) {
      el.__n = key;
      arc.setAttribute('stroke-dasharray', `${(n * 100).toFixed(2)} 100`);
      setStyle(rot, 'transform', `rotate(${(-135 + 270 * n).toFixed(2)}deg)`);
    }
    if (valEl) setText(valEl, v.text);
    setClass(el, 'learning', !!v.learning);
    setClass(el, 'mapped', !!v.mapped);
  });
  return el;
}

/** An einen Parameter gebundener Regler (Pad-Parameter beziehen sich auf das ausgewählte Pad). */
export function paramKnob(c, id, { title, size = 36, style, showValue = true, pad = null } = {}) {
  const spec = PARAMS[id];
  const target = () => pad ?? c.selectedPad;
  return knob({
    size, style, showValue, title: title ?? spec.short,
    tip: `${spec.name} – ziehen oder Mausrad, Umschalt = fein, Doppelklick = Standardwert. Rechtsklick: MIDI-Learn und XY-Zuweisung.`,
    get: () => ({
      n: c.normalized(id, target()), text: c.display(id, target()),
      learning: c.midiLearnActive && c.learnTarget === id, mapped: !!c.mappingFor(id)
    }),
    set: (n) => c.setParameter(id, n, pad),
    onBegin: () => { if (c.midiLearnActive) c.learnTarget = id; c.showParameter(id, target()); },
    reset: () => c.setParameter(id, toNormalized(id, spec.def), pad),
    menu: () => [
      { label: 'MIDI-Learn', action: () => c.beginLearn(id) },
      ...(c.mappingFor(id) ? [{ label: 'MIDI-Zuordnung entfernen', action: () => c.removeMapping(id) }] : []),
      '-',
      { label: 'Auf Touchpad X-Achse legen', action: () => c.assignXY('x', id) },
      { label: 'Auf Touchpad Y-Achse legen', action: () => c.assignXY('y', id) },
      '-',
      { label: 'Zurücksetzen', action: () => c.setParameter(id, toNormalized(id, spec.def), pad) }
    ]
  });
}

export { fromNormalized };
