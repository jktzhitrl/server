// Automatischer Screenshot-Modus (CI/Dokumentation): "NEXORA Sampler.exe --screenshots <Ordner>".
import { bridge, join } from '../core/bridge.js';
import { recordMotion } from '../engine/model.js';

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
  // Song, Motion, Sampling, Slice
  await bridge.setSize(1500, 1280);
  c.songClear(); [0, 0, 1, 0].forEach((s) => c.songAppend(s));
  c.setSongMode(true);
  const lane = (id, pad, fn) => { for (let s = 0; s < 16; s++) recordMotion(c.currentPattern, id, pad, s, fn(s)); };
  lane('padCutoff', 0, (s) => 300 * Math.pow(50, s / 15));
  lane('reverbMix', 0, (s) => (s % 8) / 10);
  c.pushPattern(c.project.sequencer.currentPattern);
  c.drawer = 'song';
  await sleep(1800);
  await shot('win-11-song-motion');
  c.setSongMode(false);
  c.drawer = 'sampling';
  c.setSampling({ targetPad: 15 });
  await sleep(600);
  await shot('win-12-sampling');
  c.drawer = 'sequencer';
  c.setPatternLength(64);
  c.setStepPage(2, true);
  await sleep(600);
  await shot('win-13-64-steps');
  c.drawer = null;
  await bridge.setSize(1500, 900);
  c.selectPad(13);
  c.dialog = 'slice';
  await sleep(800);
  await shot('win-14-slice');
  c.dialog = null;
  c.stop();
  console.log('[NEXORA] Screenshots gespeichert:', dir);
  await bridge.quit();
}
