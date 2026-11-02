// Sample-Bibliothek: eingebaute Werks-Klänge (schreibgeschützt, aus den App-Ressourcen) und
// eigene Bibliotheken im Benutzerordner (gleiches library.json-Format wie die Mac-Version).
import { bridge, join, basename, stem, extname, sanitize, isAudioPath } from './bridge.js';
import { uuid } from '../engine/model.js';

export const FACTORY_PREFIX = 'Factory · ';

export class Library {
  constructor(info) {
    this.root = join(info.dataDir, 'Library');
    this.factoryURL = info.factoryURL;
    this.factory = null;            // Manifest
    this.factoryCollections = [];   // virtuelle Sammlungen
    this.userCollections = [];
  }

  async load() {
    try {
      const res = await fetch(this.factoryURL + 'manifest.json');
      if (res.ok) this.factory = await res.json();
    } catch { this.factory = null; }
    if (this.factory) {
      this.factoryCollections = this.factory.categories.map((cat) => ({
        id: `factory:${cat}`, name: FACTORY_PREFIX + cat, isFactory: true,
        items: this.factory.sounds.filter((s) => s.category === cat).map((s) => ({
          id: `factory:${s.id}`, factoryID: s.id, name: s.name, duration: s.duration, sampleRate: this.factory.sampleRate,
          channels: s.channels, url: this.factoryURL + encodeURI(s.file).replace(/#/g, '%23'), settings: s.settings, fileExtension: 'wav'
        }))
      }));
    }
    try {
      const idx = JSON.parse(await bridge.readText(join(this.root, 'library.json')));
      this.userCollections = (idx.collections ?? []).filter((c) => !c.isFactory).map((c) => ({ ...c, isFactory: false, items: c.items ?? [] }));
    } catch { this.userCollections = []; }
    if (!this.userCollections.length) this.userCollections = [{ id: uuid(), name: 'My Samples', items: [], isFactory: false }];
  }

  get collections() { return [...this.factoryCollections, ...this.userCollections]; }
  get soundCount() { return this.factory?.sounds.length ?? 0; }

  async save() {
    const idx = { formatVersion: 1, collections: this.userCollections.map(({ id, name, items }) => ({ id, name, items, isFactory: false })) };
    await bridge.write(join(this.root, 'library.json'), JSON.stringify(idx, null, 2));
  }

  collection(id) { return this.collections.find((c) => c.id === id) ?? null; }
  item(id) { for (const c of this.collections) { const i = c.items.find((x) => x.id === id); if (i) return i; } return null; }
  collectionOf(itemId) { return this.collections.find((c) => c.items.some((i) => i.id === itemId)) ?? null; }
  factorySound(id) { return this.factory?.sounds.find((s) => s.id === id) ?? null; }
  factoryItemBySoundID(id) { return this.item(`factory:${id}`); }

  /** Pfad (Benutzer-Datei) oder URL (Werks-Klang) eines Eintrags. */
  location(item) {
    if (item.url) return { url: item.url };
    if (item.relativePath) return { path: join(this.root, ...item.relativePath.split('/')) };
    if (item.absolutePath) return { path: item.absolutePath };
    return null;
  }

  async bytes(item) {
    const loc = this.location(item);
    if (!loc) throw new Error('Unbekannter Eintrag');
    if (loc.url) {
      const res = await fetch(loc.url);
      if (!res.ok) throw new Error(`Werks-Klang nicht gefunden: ${item.name}`);
      return new Uint8Array(await res.arrayBuffer());
    }
    return bridge.read(loc.path);
  }

  async createCollection(name) {
    const c = { id: uuid(), name: name || 'New Library', items: [], isFactory: false };
    this.userCollections.push(c);
    await this.save();
    return c;
  }

  async renameCollection(id, name) {
    const c = this.userCollections.find((x) => x.id === id);
    if (c) { c.name = name; await this.save(); }
  }

  async removeCollection(id) {
    await bridge.remove(join(this.root, 'Collections', id)).catch(() => {});
    this.userCollections = this.userCollections.filter((c) => c.id !== id);
    if (!this.userCollections.length) this.userCollections.push({ id: uuid(), name: 'My Samples', items: [], isFactory: false });
    await this.save();
  }

  /**
   * Importiert Dateien (Pfade) in eine eigene Sammlung.
   * @param {(bytes:Uint8Array, name:string)=>Promise<{duration:number,sampleRate:number,channels:number}>} probe
   */
  async importFiles(paths, collectionId, copy, probe) {
    const c = this.userCollections.find((x) => x.id === collectionId) ?? this.userCollections[0];
    const imported = [], failed = [];
    for (const p of paths) {
      if (!isAudioPath(p)) { failed.push(basename(p)); continue; }
      try {
        const bytes = await bridge.read(p);
        const info = await probe(bytes, stem(p));
        const item = { id: uuid(), name: stem(p), duration: info.duration, sampleRate: info.sampleRate, channels: info.channels, addedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z') };
        if (copy) {
          const dir = join(this.root, 'Collections', c.id);
          let fileName = `${sanitize(stem(p))}.${extname(p)}`;
          let n = 2;
          while (await bridge.exists(join(dir, fileName))) fileName = `${sanitize(stem(p))} ${n++}.${extname(p)}`;
          await bridge.write(join(dir, fileName), bytes);
          item.relativePath = `Collections/${c.id}/${fileName}`;
        } else {
          item.absolutePath = p;
        }
        c.items.push(item);
        imported.push(item);
      } catch { failed.push(basename(p)); }
    }
    await this.save();
    return { imported, failed, collection: c };
  }

  /** Import aus Browser-File-Objekten ohne Dateipfad (nur Web-Modus/Drag aus fremden Quellen). */
  async importBlobs(files, collectionId, probe) {
    const c = this.userCollections.find((x) => x.id === collectionId) ?? this.userCollections[0];
    const imported = [], failed = [];
    for (const f of files) {
      try {
        const bytes = new Uint8Array(await f.arrayBuffer());
        const info = await probe(bytes, stem(f.name));
        const dir = join(this.root, 'Collections', c.id);
        const fileName = `${sanitize(stem(f.name))}-${Date.now() % 100000}.${extname(f.name) || 'wav'}`;
        await bridge.write(join(dir, fileName), bytes);
        const item = { id: uuid(), name: stem(f.name), relativePath: `Collections/${c.id}/${fileName}`, duration: info.duration,
          sampleRate: info.sampleRate, channels: info.channels, addedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z') };
        c.items.push(item);
        imported.push(item);
      } catch { failed.push(f.name); }
    }
    await this.save();
    return { imported, failed, collection: c };
  }

  async renameItem(id, name) {
    for (const c of this.userCollections) {
      const i = c.items.find((x) => x.id === id);
      if (i) { i.name = name; await this.save(); return; }
    }
  }

  async removeItem(id) {
    for (const c of this.userCollections) {
      const idx = c.items.findIndex((x) => x.id === id);
      if (idx >= 0) {
        const [item] = c.items.splice(idx, 1);
        if (item.relativePath) await bridge.remove(join(this.root, ...item.relativePath.split('/'))).catch(() => {});
        await this.save();
        return;
      }
    }
  }
}
