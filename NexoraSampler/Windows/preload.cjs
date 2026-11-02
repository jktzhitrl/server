// Sichere Brücke zwischen Oberfläche (Renderer) und Hauptprozess.
const { contextBridge, ipcRenderer, webUtils } = require('electron');

const invoke = (ch) => (...args) => ipcRenderer.invoke(ch, ...args);

contextBridge.exposeInMainWorld('nexoraNative', {
  info: invoke('app:info'),
  openFiles: invoke('dialog:openFiles'),
  openProject: invoke('dialog:openProject'),
  saveFile: invoke('dialog:saveFile'),
  saveProject: invoke('dialog:saveProject'),
  message: invoke('dialog:message'),
  read: invoke('fs:read'),
  readText: invoke('fs:readText'),
  write: invoke('fs:write'),
  exists: invoke('fs:exists'),
  isDir: invoke('fs:isDir'),
  size: invoke('fs:size'),
  list: invoke('fs:list'),
  mkdir: invoke('fs:mkdir'),
  copy: invoke('fs:copy'),
  remove: invoke('fs:remove'),
  findFile: invoke('fs:findFile'),
  writePackage: invoke('package:write'),
  showInFolder: invoke('shell:show'),
  openPath: invoke('shell:openPath'),
  setTitle: invoke('win:setTitle'),
  setSize: invoke('win:setSize'),
  capture: invoke('win:capture'),
  closeConfirmed: invoke('app:close-confirmed'),
  quit: invoke('app:quit'),
  pathForFile: (file) => { try { return webUtils.getPathForFile(file) || null; } catch { return null; } },
  onMenu: (cb) => ipcRenderer.on('menu', (_e, id) => cb(id)),
  onCloseRequest: (cb) => ipcRenderer.on('app:close-request', () => cb()),
  pathSep: process.platform === 'win32' ? '\\' : '/'
});
