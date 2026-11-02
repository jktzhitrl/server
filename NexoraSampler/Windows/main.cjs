// NEXORA Sampler – Windows: Electron-Hauptprozess (Fenster, Menüs, Dateizugriff, Dialoge).
const { app, BrowserWindow, Menu, dialog, ipcMain, protocol, net, shell, session } = require('electron');
const path = require('node:path');
const fs = require('node:fs/promises');
const fssync = require('node:fs');
const { pathToFileURL } = require('node:url');
const crypto = require('node:crypto');

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } }
]);

const SRC = path.join(__dirname, 'src');
const FACTORY = app.isPackaged ? path.join(process.resourcesPath, 'factory') : path.join(__dirname, 'resources', 'factory');
const DATA = path.join(app.getPath('appData'), 'NEXORA Sampler');
const screenshotArg = process.argv.indexOf('--screenshots');
const SCREENSHOT_DIR = screenshotArg > 0 ? process.argv[screenshotArg + 1] : null;

let win = null;
let allowClose = false;

function inside(root, p) {
  const rel = path.relative(root, p);
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function projectFromArgv(argv) {
  return argv.slice(1).find((a) => /\.nexora[\\/]?$/i.test(a) || /project\.json$/i.test(a)) ?? null;
}

function send(channel, ...args) { if (win && !win.isDestroyed()) win.webContents.send(channel, ...args); }

function buildMenu() {
  const m = (label, id, accelerator) => ({ label, accelerator, click: () => send('menu', id) });
  const template = [
    { label: '&Datei', submenu: [
      m('Neues Projekt …', 'new', 'CmdOrCtrl+N'), m('Neues leeres Projekt', 'new:empty', 'CmdOrCtrl+Shift+N'), m('Projekt öffnen …', 'open', 'CmdOrCtrl+O'),
      m('Sichern', 'save', 'CmdOrCtrl+S'), m('Sichern unter …', 'saveAs', 'CmdOrCtrl+Shift+S'),
      { type: 'separator' },
      m('Samples importieren …', 'import', 'CmdOrCtrl+I'), m('Sample auf ausgewähltes Pad laden …', 'loadSample', 'CmdOrCtrl+L'),
      { type: 'separator' },
      m('Audio exportieren …', 'export', 'CmdOrCtrl+E'), m('Einstellungen …', 'settings', 'CmdOrCtrl+,'),
      { type: 'separator' }, { role: 'quit', label: 'Beenden' }
    ] },
    { label: '&Transport', submenu: [
      m('Play / Stop (Leertaste)', 'togglePlay', 'CmdOrCtrl+Enter'), m('Pause', 'pause', 'CmdOrCtrl+.'),
      m('Aufnahme', 'record', 'CmdOrCtrl+R'), m('Metronom', 'metronome', 'CmdOrCtrl+K'), m('Tap Tempo', 'tap', 'CmdOrCtrl+T'),
      { type: 'separator' },
      ...'ABCDEFGH'.split('').map((l, i) => m(`Pattern ${l}`, `pattern:${i}`, `CmdOrCtrl+${i + 1}`))
    ] },
    { label: '&Pads', submenu: [
      m('Trigger-Modus', 'mode:play', 'CmdOrCtrl+Alt+P'), m('Sequencer-Modus', 'mode:step', 'CmdOrCtrl+Alt+T'),
      m('Keyboard-Modus', 'mode:keyboard', 'CmdOrCtrl+Alt+K'),
      m('Keyboard: Oktave höher', 'octave:+1', 'CmdOrCtrl+Alt+Up'), m('Keyboard: Oktave tiefer', 'octave:-1', 'CmdOrCtrl+Alt+Down'),
      { type: 'separator' },
      m('Pad-Editor', 'drawer:editor', 'CmdOrCtrl+Alt+1'), m('Sequencer', 'drawer:sequencer', 'CmdOrCtrl+Alt+2'),
      m('Sample-Browser', 'drawer:browser', 'CmdOrCtrl+Alt+3'), m('Master-Effekte', 'drawer:effects', 'CmdOrCtrl+Alt+4'),
      m('Kits & Presets', 'drawer:kits', 'CmdOrCtrl+Alt+5'), m('MIDI', 'drawer:midi', 'CmdOrCtrl+Alt+6'),
      m('Bereich schließen', 'drawer:none', 'CmdOrCtrl+Alt+0'),
      { type: 'separator' }, m('MIDI-Learn', 'learn', 'CmdOrCtrl+Shift+M'), m('Alle Noten aus', 'panic', 'Shift+Escape')
    ] },
    { label: '&Ansicht', submenu: [
      { role: 'togglefullscreen', label: 'Vollbild' }, { role: 'resetZoom', label: 'Originalgröße' },
      { type: 'separator' }, { role: 'toggleDevTools', label: 'Entwicklerwerkzeuge' }
    ] },
    { label: '&Hilfe', submenu: [
      { label: 'Anleitung', accelerator: 'F1', click: openHelp }
    ] }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

let helpWin = null;

function openHelp() {
  if (helpWin && !helpWin.isDestroyed()) { helpWin.focus(); return; }
  helpWin = new BrowserWindow({
    width: 980, height: 860, minWidth: 420, minHeight: 400, title: 'NEXORA Sampler – Anleitung',
    icon: path.join(__dirname, 'build', 'icon.png'), autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  helpWin.loadURL('app://nexora/help/anleitung.html');
  helpWin.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  helpWin.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('app://nexora/help/')) e.preventDefault(); });
  helpWin.on('closed', () => { helpWin = null; });
}

function createWindow() {
  win = new BrowserWindow({
    width: 1440, height: 900, minWidth: 960, minHeight: 540, backgroundColor: '#0e0c10',
    title: 'NEXORA Sampler', icon: path.join(__dirname, 'build', 'icon.png'), show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: false,
      backgroundThrottling: false, autoplayPolicy: 'no-user-gesture-required'
    }
  });
  win.once('ready-to-show', () => win.show());
  win.loadURL('app://nexora/index.html');
  win.on('close', (e) => {
    if (allowClose || SCREENSHOT_DIR) return;
    e.preventDefault();
    send('app:close-request');
  });
  win.on('closed', () => { win = null; if (helpWin && !helpWin.isDestroyed()) helpWin.close(); });
}

// --------------------------------------------------------------- IPC

const filtersFor = (kind) => ({
  audio: [{ name: 'Audiodateien', extensions: ['wav', 'wave', 'aif', 'aiff', 'aifc', 'mp3', 'm4a', 'aac', 'flac', 'ogg'] }],
  wav: [{ name: 'WAV', extensions: ['wav'] }],
  aiff: [{ name: 'AIFF', extensions: ['aif', 'aiff'] }],
  json: [{ name: 'JSON', extensions: ['json'] }]
}[kind] ?? []);

function registerIPC() {
  ipcMain.handle('app:info', () => ({
    dataDir: DATA, factoryURL: 'app://factory/', documents: app.getPath('documents'), music: app.getPath('music'),
    version: app.getVersion(), platform: process.platform, screenshots: SCREENSHOT_DIR,
    openProject: projectFromArgv(process.argv)
  }));
  ipcMain.handle('dialog:openFiles', async (_e, { kind = 'audio', multi = false, title } = {}) => {
    const r = await dialog.showOpenDialog(win, { title, properties: ['openFile', ...(multi ? ['multiSelections'] : [])], filters: filtersFor(kind) });
    return r.canceled ? [] : r.filePaths;
  });
  ipcMain.handle('dialog:openProject', async () => {
    const r = await dialog.showOpenDialog(win, {
      title: 'NEXORA-Projekt öffnen (Ordner .nexora oder project.json)', properties: ['openFile', 'openDirectory'],
      filters: [{ name: 'NEXORA-Projekt', extensions: ['json', 'nexora'] }]
    });
    return r.canceled ? null : r.filePaths[0];
  });
  ipcMain.handle('dialog:saveFile', async (_e, { defaultName, kind, title }) => {
    const r = await dialog.showSaveDialog(win, { title, defaultPath: path.join(app.getPath('documents'), defaultName), filters: filtersFor(kind) });
    return r.canceled ? null : r.filePath;
  });
  ipcMain.handle('dialog:saveProject', async (_e, { defaultName }) => {
    const r = await dialog.showSaveDialog(win, {
      title: 'Projekt inklusive aller Samples speichern', defaultPath: path.join(app.getPath('documents'), `${defaultName}.nexora`),
      filters: [{ name: 'NEXORA-Projekt', extensions: ['nexora'] }]
    });
    if (r.canceled) return null;
    return r.filePath.toLowerCase().endsWith('.nexora') ? r.filePath : `${r.filePath}.nexora`;
  });
  ipcMain.handle('dialog:message', async (_e, opts) => (await dialog.showMessageBox(win, opts)).response);

  ipcMain.handle('fs:read', async (_e, p) => new Uint8Array(await fs.readFile(p)));
  ipcMain.handle('fs:readText', async (_e, p) => fs.readFile(p, 'utf8'));
  ipcMain.handle('fs:write', async (_e, p, data) => {
    await fs.mkdir(path.dirname(p), { recursive: true });
    const tmp = `${p}.tmp-${crypto.randomUUID()}`;
    await fs.writeFile(tmp, typeof data === 'string' ? data : Buffer.from(data));
    await fs.rename(tmp, p);
  });
  ipcMain.handle('fs:exists', async (_e, p) => fssync.existsSync(p));
  ipcMain.handle('fs:isDir', async (_e, p) => { try { return (await fs.stat(p)).isDirectory(); } catch { return false; } });
  ipcMain.handle('fs:size', async (_e, p) => { try { return (await fs.stat(p)).size; } catch { return null; } });
  ipcMain.handle('fs:list', async (_e, p) => { try { return await fs.readdir(p); } catch { return []; } });
  ipcMain.handle('fs:mkdir', async (_e, p) => fs.mkdir(p, { recursive: true }));
  ipcMain.handle('fs:copy', async (_e, src, dst) => { await fs.mkdir(path.dirname(dst), { recursive: true }); await fs.copyFile(src, dst); });
  ipcMain.handle('fs:remove', async (_e, p) => {
    if (!inside(DATA, p)) throw new Error('Löschen ist nur im Datenordner von NEXORA erlaubt.');
    await fs.rm(p, { recursive: true, force: true });
  });
  ipcMain.handle('fs:findFile', async (_e, roots, fileName, wantedSize) => {
    const lower = fileName.toLowerCase();
    const hits = [];
    const walk = async (dir, depth) => {
      if (depth > 6 || hits.length > 20) return;
      let entries = [];
      try { entries = await fs.readdir(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        if (e.name.startsWith('.')) continue;
        const full = path.join(dir, e.name);
        if (e.isDirectory()) await walk(full, depth + 1);
        else if (e.name.toLowerCase() === lower) hits.push(full);
      }
    };
    for (const r of roots) await walk(r, 0);
    if (wantedSize != null) {
      for (const h of hits) { try { if ((await fs.stat(h)).size === wantedSize) return h; } catch {} }
    }
    return hits[0] ?? null;
  });

  /** Schreibt ein Projekt- oder Kit-Paket atomar (Staging-Ordner, dann Austausch). */
  ipcMain.handle('package:write', async (_e, { target, manifestName, json, files }) => {
    const parent = path.dirname(target);
    await fs.mkdir(parent, { recursive: true });
    const staging = path.join(parent, `.${path.basename(target)}.saving-${crypto.randomUUID()}`);
    await fs.mkdir(path.join(staging, 'Samples'), { recursive: true });
    try {
      for (const f of files) {
        const dst = path.join(staging, f.rel);
        if (f.source) await fs.copyFile(f.source, dst);
        else await fs.writeFile(dst, Buffer.from(f.data));
      }
      await fs.writeFile(path.join(staging, manifestName), json, 'utf8');
      if (fssync.existsSync(target)) {
        const backup = path.join(parent, `.${path.basename(target)}.backup-${crypto.randomUUID()}`);
        await fs.rename(target, backup);
        try { await fs.rename(staging, target); } catch (err) { await fs.rename(backup, target); throw err; }
        await fs.rm(backup, { recursive: true, force: true });
      } else {
        await fs.rename(staging, target);
      }
    } catch (err) {
      await fs.rm(staging, { recursive: true, force: true });
      throw err;
    }
  });

  ipcMain.handle('shell:show', (_e, p) => shell.showItemInFolder(p));
  ipcMain.handle('shell:openPath', (_e, p) => shell.openPath(p));
  ipcMain.handle('win:setTitle', (_e, t) => { if (win) win.setTitle(t); });
  ipcMain.handle('win:setSize', (_e, w, h) => { if (win) { win.setContentSize(w, h); win.center(); } });
  ipcMain.handle('win:capture', async (_e, file) => {
    const img = await win.webContents.capturePage();
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, img.toPNG());
    return file;
  });
  ipcMain.handle('app:close-confirmed', () => { allowClose = true; if (win) win.close(); });
  ipcMain.handle('app:quit', () => { allowClose = true; app.quit(); });
}

// --------------------------------------------------------------- Start

const single = app.requestSingleInstanceLock();
if (!single) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
    const p = projectFromArgv(argv);
    if (p) send('menu', `openPath:${p}`);
  });

  app.whenReady().then(() => {
    protocol.handle('app', (req) => {
      const url = new URL(req.url);
      const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '');
      const root = url.host === 'factory' ? FACTORY : SRC;
      const file = path.normalize(path.join(root, rel));
      if (!inside(root, file)) return new Response('Forbidden', { status: 403 });
      return net.fetch(pathToFileURL(file).toString());
    });
    const allowed = new Set(['midi', 'midiSysex', 'speaker-selection', 'media']);
    session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(allowed.has(perm)));
    session.defaultSession.setPermissionCheckHandler((_wc, perm) => allowed.has(perm));
    registerIPC();
    buildMenu();
    createWindow();
  });
  app.on('window-all-closed', () => app.quit());
}
