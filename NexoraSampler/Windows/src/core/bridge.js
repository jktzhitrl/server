// Zugriff auf Dateisystem und Dialoge. In Electron über den Preload (nexoraNative),
// im normalen Browser (Entwicklung/Screenshots) über eine In-Memory-Nachbildung.

const native = globalThis.nexoraNative;
export const isNative = !!native;

function webFallback() {
  const files = new Map();
  const under = (p) => [...files.keys()].filter((k) => k.startsWith(p + '/'));
  const factoryURL = new URL('../resources/factory/', globalThis.location?.href ?? 'http://localhost/').href;
  return {
    info: async () => ({ dataDir: '/appdata', factoryURL, documents: '/docs', music: '/music', platform: 'web', screenshots: null, openProject: null, version: 'web' }),
    openFiles: async () => [], openProject: async () => null, saveFile: async () => null, saveProject: async () => null,
    message: async (o) => ((o.buttons?.length ?? 1) > 1 ? (globalThis.confirm?.(o.message) ? 0 : (o.buttons.length - 1)) : 0),
    read: async (p) => { if (!files.has(p)) throw new Error(`Datei nicht gefunden: ${p}`); const v = files.get(p); return typeof v === 'string' ? new TextEncoder().encode(v) : v; },
    readText: async (p) => { if (!files.has(p)) throw new Error(`Datei nicht gefunden: ${p}`); const v = files.get(p); return typeof v === 'string' ? v : new TextDecoder().decode(v); },
    write: async (p, d) => { files.set(p, d); },
    exists: async (p) => files.has(p) || under(p).length > 0,
    isDir: async (p) => under(p).length > 0,
    size: async (p) => files.get(p)?.length ?? null,
    list: async (p) => [...new Set(under(p).map((k) => k.slice(p.length + 1).split('/')[0]))],
    mkdir: async () => {},
    copy: async (a, b) => { files.set(b, files.get(a)); },
    remove: async (p) => { files.delete(p); for (const k of under(p)) files.delete(k); },
    findFile: async () => null,
    writePackage: async ({ target, manifestName, json, files: list }) => {
      for (const k of under(target)) files.delete(k);
      for (const f of list) files.set(`${target}/${f.rel}`, f.data ?? files.get(f.source));
      files.set(`${target}/${manifestName}`, json);
    },
    showInFolder: async () => {}, openPath: async () => {},
    setTitle: async (t) => { if (globalThis.document) document.title = t; },
    setSize: async () => {}, capture: async () => null, closeConfirmed: async () => {}, quit: async () => {},
    pathForFile: () => null, onMenu: () => {}, onCloseRequest: () => {}, pathSep: '/'
  };
}

export const bridge = native ?? webFallback();

const SEP_RE = /[\\/]+/;
export const sep = () => bridge.pathSep;
export function join(...parts) {
  const s = sep();
  return parts.filter((p) => p != null && p !== '').map((p, i) => {
    const str = String(p);
    return i === 0 ? str.replace(/[\\/]+$/, '') : str.replace(/^[\\/]+|[\\/]+$/g, '');
  }).join(s).split(SEP_RE).join(s).replace(/^([A-Za-z]:)$/, '$1' + s);
}
export const basename = (p) => String(p).split(SEP_RE).filter(Boolean).pop() ?? '';
export const dirname = (p) => {
  const parts = String(p).split(SEP_RE);
  parts.pop();
  const d = parts.join(sep());
  return d || sep();
};
export const extname = (p) => { const b = basename(p); const i = b.lastIndexOf('.'); return i > 0 ? b.slice(i + 1).toLowerCase() : ''; };
export const stem = (p) => { const b = basename(p); const i = b.lastIndexOf('.'); return i > 0 ? b.slice(0, i) : b; };

export const sanitize = (name) => {
  const cleaned = String(name).replace(/[\/\\:?%*|"<>\n\r\t]/g, '_').trim();
  return (cleaned || 'Sample').slice(0, 80);
};

export const AUDIO_EXTENSIONS = new Set(['wav', 'wave', 'aif', 'aiff', 'aifc', 'mp3', 'm4a', 'aac', 'flac', 'ogg']);
export const isAudioPath = (p) => AUDIO_EXTENSIONS.has(extname(p));
