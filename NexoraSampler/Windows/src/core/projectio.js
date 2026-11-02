// Projekt-, Kit- und Preset-Dateien. Formate identisch zur Mac-Version
// (siehe docs/PROJECT_FORMAT.md): Projekt = Ordner "Name.nexora" mit project.json + Samples/.
import { bridge, join, basename, dirname, extname, stem, sanitize } from './bridge.js';
import { encodeAudio } from '../engine/audiofile.js';
import { normalizeProject, normalizePattern, defaultMaster, defaultPadSettings, compactProject, compactPattern } from '../engine/model.js';

const iso = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

function sortedJSON(value) {
  const sort = (v) => {
    if (Array.isArray(v)) return v.map(sort);
    if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => [k, sort(v[k])]));
    return v;
  };
  return JSON.stringify(sort(value), null, 2);
}

/**
 * Schreibt Samples in ein Paket und liefert aktualisierte Pad-Konfigurationen und die Dateiliste.
 * sources[i]: { type: 'file', path } | { type: 'bytes', bytes, ext } | { type: 'buffer', sample } | null
 */
function packageFiles(pads, sources) {
  const files = [];
  // Pads mit derselben Quelle (z. B. Slices eines Samples) teilen sich eine Datei im Paket.
  const shared = new Map();
  const keyOf = (src) => (src.type === 'file' ? `file:${src.path}` : src.type === 'bytes' ? src.bytes : src.sample);
  const out = pads.map((pad, i) => {
    const src = sources[i];
    const prefix = String(i + 1).padStart(2, '0') + '-';
    const copy = { ...pad };
    if (!src) { delete copy.sample; return copy; }
    const ref = { ...(pad.sample ?? {}) };
    const known = shared.get(keyOf(src));
    if (known) {
      copy.sample = { ...ref, ...known };
      return copy;
    }
    if (src.type === 'file') {
      const name = `${prefix}${sanitize(stem(src.path))}.${extname(src.path) || 'wav'}`;
      files.push({ rel: `Samples/${name}`, source: src.path });
      ref.fileName = ref.fileName || basename(src.path);
      ref.originalPath = ref.originalPath ?? src.path;
      ref.packagePath = `Samples/${name}`;
    } else if (src.type === 'bytes') {
      const name = `${prefix}${sanitize(src.name)}.${src.ext || 'wav'}`;
      files.push({ rel: `Samples/${name}`, data: src.bytes });
      ref.fileName = ref.fileName || `${src.name}.${src.ext || 'wav'}`;
      ref.packagePath = `Samples/${name}`;
      ref.fileSize = src.bytes.length;
    } else {
      const s = src.sample;
      const name = `${prefix}${sanitize(s.name || pad.name)}.wav`;
      const data = encodeAudio(s.left, s.right, s.sampleRate, 'wav', 'float32', { dither: false, mono: !s.stereo });
      files.push({ rel: `Samples/${name}`, data });
      ref.fileName = ref.fileName || name;
      ref.packagePath = `Samples/${name}`;
      ref.frameCount = s.frameCount;
      ref.sampleRate = s.sampleRate;
      ref.fileSize = data.length;
    }
    copy.sample = ref;
    const { packagePath, fileName, fileSize, frameCount, sampleRate, originalPath } = ref;
    shared.set(keyOf(src), Object.fromEntries(Object.entries({ packagePath, fileName, fileSize, frameCount, sampleRate, originalPath }).filter(([, v]) => v !== undefined)));
    return copy;
  });
  return { pads: out, files };
}

export async function writeProject(target, project, sources) {
  const doc = structuredClone(compactProject(project));
  doc.modifiedAt = iso();
  doc.format = 'de.nexora.sampler.project';
  doc.formatVersion = 1;
  const { pads, files } = packageFiles(doc.pads, sources);
  doc.pads = pads;
  await bridge.writePackage({ target, manifestName: 'project.json', json: sortedJSON(doc), files });
  return doc;
}

export const packageDirFor = (p) => (basename(p).toLowerCase() === 'project.json' ? dirname(p) : p);

export async function readProject(pathOrDir) {
  const dir = packageDirFor(pathOrDir);
  let text;
  try { text = await bridge.readText(join(dir, 'project.json')); } catch { throw new Error('Im Projektordner fehlt die Datei project.json.'); }
  return { dir, project: normalizeProject(JSON.parse(text)) };
}

/**
 * Findet die Datei zu einer SampleReference (gleiche Reihenfolge wie SampleResolver auf dem Mac):
 * Paket → Bibliothek → Originalpfad → Suche nach Dateiname.
 */
export async function resolveSample(ref, packageDir, library, searchRoots) {
  if (!ref) return null;
  if (packageDir && ref.packagePath) {
    const p = join(packageDir, ...ref.packagePath.split('/'));
    if (await bridge.exists(p)) return { path: p };
  }
  if (ref.libraryItemID) {
    const item = library.item(ref.libraryItemID) ?? library.item(`factory:${ref.libraryItemID}`);
    if (item) return { item };
  }
  if (ref.originalPath && await bridge.exists(ref.originalPath)) return { path: ref.originalPath };
  if (ref.fileName) {
    const found = await bridge.findFile(searchRoots.filter(Boolean), ref.fileName, ref.fileSize ?? null);
    if (found) return { path: found };
  }
  return null;
}

// ---------------------------------------------------------------- Presets

export class PresetStore {
  constructor(info) {
    this.root = join(info.dataDir, 'Presets');
    this.kinds = { kit: ['Kits', 'nexorakit'], effects: ['Effects', 'nexorafx'], pattern: ['Patterns', 'nexorapattern'] };
  }
  folder(kind) { return join(this.root, this.kinds[kind][0]); }
  pathFor(kind, name) { return join(this.folder(kind), `${sanitize(name)}.${this.kinds[kind][1]}`); }

  async list(kind) {
    const ext = `.${this.kinds[kind][1]}`;
    const names = (await bridge.list(this.folder(kind))).filter((n) => n.endsWith(ext));
    return names.map((n) => ({ name: n.slice(0, -ext.length), path: join(this.folder(kind), n), kind }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  async remove(info) { await bridge.remove(info.path); }

  async saveKit(name, pads, sources) {
    const target = this.pathFor('kit', name);
    const { pads: packaged, files } = packageFiles(structuredClone(pads), sources);
    await bridge.writePackage({ target, manifestName: 'kit.json', json: sortedJSON({ format: 'de.nexora.sampler.kit', formatVersion: 1, name, pads: packaged }), files });
    return target;
  }

  async loadKit(info) {
    const kit = JSON.parse(await bridge.readText(join(info.path, 'kit.json')));
    const doc = normalizeProject({ formatVersion: 1, pads: kit.pads ?? [] });
    return { name: kit.name ?? info.name, pads: doc.pads, dir: info.path };
  }

  async saveEffects(name, master) {
    await bridge.write(this.pathFor('effects', name), sortedJSON({ format: 'de.nexora.sampler.effects', formatVersion: 1, name, master }));
  }

  async loadEffects(info) {
    const j = JSON.parse(await bridge.readText(info.path));
    return { name: j.name ?? info.name, master: { ...defaultMaster(), ...(j.master ?? {}) } };
  }

  async savePattern(name, pattern, bpm, swing) {
    await bridge.write(this.pathFor('pattern', name), sortedJSON({ format: 'de.nexora.sampler.pattern', formatVersion: 1, name, pattern: { ...compactPattern(pattern), name }, bpm, swing }));
  }

  async loadPattern(info) {
    const j = JSON.parse(await bridge.readText(info.path));
    return { name: j.name ?? info.name, pattern: normalizePattern(j.pattern), bpm: j.bpm ?? 120, swing: j.swing ?? 50 };
  }
}

export { defaultPadSettings };
