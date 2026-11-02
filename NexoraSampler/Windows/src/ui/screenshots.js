// Automatischer Screenshot-Modus (CI/Dokumentation): "NEXORA Sampler.exe --screenshots <Ordner>".
import { bridge, join } from '../core/bridge.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function runScreenshots(c, dir) {
  const shot = async (name) => { c.changed(); await sleep(400); await bridge.capture(join(dir, `${name}.png`)); };
  await bridge.setSize(1500, 900);
  await sleep(1500);
  c.setXY(0.62, 0.35);
  c.selectPad(1);
  c.play();
  await sleep(1400);
  for (const p of [0, 4, 9, 13]) c.send({ cmd: 'noteOn', pad: p, velocity: 1 });
  await sleep(80);
  await shot('win-01-instrument');
  await bridge.setSize(1500, 1280);
  for (const [d, name] of [['sequencer', 'win-02-sequencer'], ['editor', 'win-03-pad-editor'], ['browser', 'win-04-browser'],
    ['effects', 'win-05-effects'], ['kits', 'win-06-kits'], ['midi', 'win-07-midi']]) {
    c.drawer = d;
    if (d === 'browser') { c.selectedCollection = c.library.factoryCollections[0]?.id; c.selectedItem = c.library.factoryCollections[0]?.items[0]?.id; c.libraryRevision++; }
    if (d === 'editor') c.selectPad(0);
    await sleep(600);
    await shot(name);
  }
  c.drawer = null;
  await bridge.setSize(1500, 900);
  c.selectPad(4);
  c.setPadMode('step');
  await sleep(800);
  await shot('win-08-step-mode');
  c.selectPad(14);
  c.setPadMode('keyboard');
  await sleep(500);
  await shot('win-09-keyboard-mode');
  c.setPadMode('play');
  c.setPref('theme', 'lilac');
  await sleep(800);
  await shot('win-10-theme-lilac');
  c.setPref('theme', 'crimson');
  c.stop();
  console.log('[NEXORA] Screenshots gespeichert:', dir);
  await bridge.quit();
}
