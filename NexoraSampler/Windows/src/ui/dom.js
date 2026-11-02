// Kleine DOM-Hilfen und Render-Registrierung (jede Komponente meldet eine update()-Funktion an).

export const updaters = [];
export const onUpdate = (fn) => { updaters.push(fn); return fn; };

export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props ?? {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'text') el.textContent = v;
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}

/** Setzt Text nur bei Änderung. */
export function setText(el, value) {
  const v = String(value);
  if (el.__t !== v) { el.__t = v; el.textContent = v; }
}

export function setClass(el, name, on) {
  if (el.classList.contains(name) !== !!on) el.classList.toggle(name, !!on);
}

export function setStyle(el, prop, value) {
  const key = `__s_${prop}`;
  if (el[key] !== value) { el[key] = value; el.style.setProperty(prop, value); }
}

export const pad2 = (n) => String(n).padStart(2, '0');

const ICONS = {
  record: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7"/></svg>',
  stop: '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="1.5"/></svg>',
  playpause: '<svg viewBox="0 0 24 24"><path d="M3 5v14l9-7z"/><rect x="14" y="5" width="3" height="14"/><rect x="19" y="5" width="3" height="14"/></svg>',
  left: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7" stroke="currentColor" stroke-width="3" fill="none" stroke-linecap="round"/></svg>',
  right: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" stroke="currentColor" stroke-width="3" fill="none" stroke-linecap="round"/></svg>',
  chevronDown: '<svg viewBox="0 0 24 24"><path d="M5 9l7 7 7-7" stroke="currentColor" stroke-width="3" fill="none" stroke-linecap="round"/></svg>'
};

/**
 * Gummitaste mit aufgedruckter Beschriftung.
 * @param {{title?:string, icon?:string, width:number, height:number, font?:number, tip?:string, onClick:Function, lit?:()=>boolean, litColor?:string|(()=>string), fill?:boolean|(()=>boolean)}} o
 */
export function faceButton(o) {
  const el = h('button', { class: 'fbtn', title: o.tip ?? o.title ?? '', style: { width: `${o.width}px`, height: `${o.height}px`, fontSize: `${o.font ?? 10.5}px` } });
  if (o.icon) el.insertAdjacentHTML('beforeend', ICONS[o.icon]);
  const label = h('span', { text: o.title ?? '' });
  if (o.title) el.append(label);
  el.addEventListener('click', (e) => { e.stopPropagation(); o.onClick?.(e); });
  el.update = () => {
    const lit = o.lit ? o.lit() : false;
    setClass(el, 'lit', lit);
    const fill = typeof o.fill === 'function' ? o.fill() : !!o.fill;
    setClass(el, 'fill', lit && fill);
    const color = typeof o.litColor === 'function' ? o.litColor() : o.litColor;
    if (color) setStyle(el, '--lit', color);
    if (o.dynamicTitle) setText(label, o.dynamicTitle());
  };
  onUpdate(el.update);
  return el;
}

export function led(color, isOn) {
  const el = h('i', { class: 'led', style: { '--led-color': color } });
  el.style.setProperty('--led-color', color);
  onUpdate(() => setClass(el, 'on', isOn()));
  return el;
}

/** Segment-Auswahl im Drawer. */
export function segment(options, get, set) {
  const el = h('div', { class: 'seg' });
  const buttons = options.map(([value, label]) => {
    const b = h('button', { text: label, onclick: () => set(value) });
    el.append(b);
    return [value, b];
  });
  onUpdate(() => { const cur = get(); for (const [v, b] of buttons) setClass(b, 'on', v === cur); });
  return el;
}

// ------------------------------------------------------------ Kontextmenü

let openMenu = null;
export function contextMenu(x, y, items) {
  closeMenu();
  const el = h('div', { class: 'ctx', style: { left: `${x}px`, top: `${y}px` } });
  for (const it of items) {
    if (it === '-') { el.append(h('hr')); continue; }
    el.append(h('div', { text: it.label, onclick: () => { closeMenu(); it.action(); } }));
  }
  document.body.append(el);
  const r = el.getBoundingClientRect();
  if (r.right > innerWidth) el.style.left = `${innerWidth - r.width - 4}px`;
  if (r.bottom > innerHeight) el.style.top = `${innerHeight - r.height - 4}px`;
  openMenu = el;
  setTimeout(() => addEventListener('pointerdown', onAway, { capture: true }), 0);
}
function onAway(e) { if (openMenu && !openMenu.contains(e.target)) closeMenu(); }
export function closeMenu() {
  if (openMenu) { openMenu.remove(); openMenu = null; }
  removeEventListener('pointerdown', onAway, { capture: true });
}
