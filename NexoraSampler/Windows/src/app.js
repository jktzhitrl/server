// NEXORA Sampler – Windows: Start der Oberfläche.
import { Controller } from './core/controller.js';
import { updaters, h } from './ui/dom.js';
import { buildBody } from './ui/body.js';
import { buildDrawer } from './ui/drawers.js';
import { buildDialogs } from './ui/dialogs.js';
import { runScreenshots } from './ui/screenshots.js';

const c = new Controller();
globalThis.nexora = c;

const canvas = document.getElementById('canvas');
const overlay = document.getElementById('overlay');
const body = buildBody(c);
const drawerWrap = h('div');
let drawer = null;
canvas.append(body, drawerWrap);
buildDialogs(c, overlay);

let dirty = true;
c.on(() => { dirty = true; });

let drawerShown = null;
let themeApplied = null;
function layout() {
  const open = !!c.drawer && !!drawer;
  if (open !== drawerShown) {
    drawerShown = open;
    drawerWrap.replaceChildren(...(open ? [drawer] : []));
  }
  const W = 1360, H = 742 + 40 + (open ? 330 + 14 : 0);
  const scale = Math.max(0.35, Math.min(innerWidth / W, innerHeight / H));
  canvas.style.transform = `scale(${scale})`;
  canvas.__scale = scale;
}

function frame() {
  if (c.prefs.theme !== themeApplied) {
    themeApplied = c.prefs.theme;
    document.body.className = `theme-${themeApplied}`;
    dirty = true;
  }
  if (dirty) {
    dirty = false;
    layout();
    for (const fn of updaters) fn();
  }
  requestAnimationFrame(frame);
}

addEventListener('resize', () => { dirty = true; });
addEventListener('keydown', (e) => { if (c.handleKey(e, true)) e.preventDefault(); });
addEventListener('keyup', (e) => { if (c.handleKey(e, false)) e.preventDefault(); });
addEventListener('dragover', (e) => e.preventDefault());
addEventListener('drop', (e) => e.preventDefault());
addEventListener('contextmenu', (e) => { if (!e.target.closest('input, textarea')) e.preventDefault(); });

requestAnimationFrame(frame);
c.init().then(() => {
  drawer = buildDrawer(c);
  dirty = true;
  if (c.info.screenshots) runScreenshots(c, c.info.screenshots);
}).catch((err) => {
  console.error(err);
  c.report('Start fehlgeschlagen', err.message ?? String(err));
});
