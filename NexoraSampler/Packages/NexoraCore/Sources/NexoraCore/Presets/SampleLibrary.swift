import Foundation

public struct SampleLibraryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Pfad relativ zum Bibliotheksordner (bei kopierten Dateien)
    public var relativePath: String?
    /// Absoluter Pfad (bei referenzierten, nicht kopierten Dateien)
    public var absolutePath: String?
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var addedAt: Date

    public var fileExtension: String {
        URL(fileURLWithPath: relativePath ?? absolutePath ?? "").pathExtension.lowercased()
    }
}

public struct SampleLibraryCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [SampleLibraryItem]
    /// Teil der eingebauten Werks-Bibliothek (wird bei neuer Version ersetzt)
    public var isFactory: Bool

    public init(name: String, isFactory: Bool = false) {
        id = UUID()
        self.name = name
        items = []
        self.isFactory = isFactory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Library")
        items = c.value(.items, default: [])
        isFactory = c.value(.isFactory, default: false)
    }
}

/// Benutzerdefinierte Sample-Bibliotheken. Importierte Dateien werden standardmäßig in den
/// Bibliotheksordner kopiert, damit sie dauerhaft verfügbar bleiben.
///
/// Aufbau: `<root>/library.json` und `<root>/Collections/<Sammlungs-ID>/<Datei>`.
public final class SampleLibrary {
    public static let indexFileName = "library.json"

    public let root: URL
    public private(set) var collections: [SampleLibraryCollection]

    private struct Index: Codable {
        var formatVersion = 1
        var collections: [SampleLibraryCollection]
    }

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let indexURL = root.appendingPathComponent(Self.indexFileName)
        if let data = try? Data(contentsOf: indexURL),
           let index = try? SamplePackager.decoder.decode(Index.self, from: data) {
            collections = index.collections
        } else {
            collections = [SampleLibraryCollection(name: "My Samples")]
        }
    }

    public func save() throws {
        let data = try SamplePackager.encoder.encode(Index(collections: collections))
        try data.write(to: root.appendingPathComponent(Self.indexFileName), options: .atomic)
    }

    private func folder(for collectionID: UUID) -> URL {
        root.appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent(collectionID.uuidString, isDirectory: true)
    }

    // MARK: Sammlungen

    @discardableResult
    public func createCollection(name: String) throws -> SampleLibraryCollection {
        let c = SampleLibraryCollection(name: name.isEmpty ? "New Library" : name)
        collections.append(c)
        try save()
        return c
    }

    public func renameCollection(_ id: UUID, to name: String) throws {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[i].name = name
        try save()
    }

    public func removeCollection(_ id: UUID, deleteFiles: Bool) throws {
        collections.removeAll { $0.id == id }
        if deleteFiles { try? FileManager.default.removeItem(at: folder(for: id)) }
        if !collections.contains(where: { !$0.isFactory }) { collections.insert(SampleLibraryCollection(name: "My Samples"), at: 0) }
        try save()
    }

    // MARK: Einträge

    /// Importiert eine Audiodatei.
    /// - Parameters:
    ///   - copy: `true` kopiert die Datei in die Bibliothek (empfohlen), sonst wird sie referenziert.
    @discardableResult
    public func importFile(_ url: URL, into collectionID: UUID, copy: Bool,
                           duration: Double, sampleRate: Double, channels: Int) throws -> SampleLibraryItem {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }) else {
            throw ProjectError.invalidPackage("Unbekannte Bibliothek")
        }
        var item = SampleLibraryItem(id: UUID(), name: url.deletingPathExtension().lastPathComponent,
                               relativePath: nil, absolutePath: nil, duration: duration,
                               sampleRate: sampleRate, channels: channels, addedAt: Date())
        if copy {
            let fm = FileManager.default
            let dir = folder(for: collectionID)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let base = SamplePackager.sanitize(url.deletingPathExtension().lastPathComponent)
            let ext = url.pathExtension
            var fileName = base + (ext.isEmpty ? "" : "." + ext)
            var counter = 2
            while fm.fileExists(atPath: dir.appendingPathComponent(fileName).path) {
                fileName = "\(base) \(counter)" + (ext.isEmpty ? "" : "." + ext)
                counter += 1
            }
            try fm.copyItem(at: url, to: dir.appendingPathComponent(fileName))
            item.relativePath = "Collections/\(collectionID.uuidString)/\(fileName)"
        } else {
            item.absolutePath = url.path
        }
        collections[ci].items.append(item)
        try save()
        return item
    }

    /// Legt eine Sammlung an, ohne sofort zu speichern (für Massenimporte).
    func appendCollection(_ collection: SampleLibraryCollection) {
        collections.append(collection)
    }

    /// Schreibt erzeugte Audiodaten direkt in eine Sammlung (ohne Quelldatei).
    func addGeneratedItem(name: String, fileName: String, data: Data, into collectionID: UUID,
                          duration: Double, sampleRate: Double, channels: Int) throws -> SampleLibraryItem {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }) else {
            throw ProjectError.invalidPackage("Unbekannte Bibliothek")
        }
        let dir = folder(for: collectionID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        let item = SampleLibraryItem(id: UUID(), name: name, relativePath: "Collections/\(collectionID.uuidString)/\(fileName)",
                                     absolutePath: nil, duration: duration, sampleRate: sampleRate, channels: channels, addedAt: Date())
        collections[ci].items.append(item)
        return item
    }

    /// Entfernt alle Werks-Sammlungen samt Dateien.
    func removeFactoryCollections() {
        for c in collections where c.isFactory { try? FileManager.default.removeItem(at: folder(for: c.id)) }
        collections.removeAll { $0.isFactory }
    }

    /// Sucht einen Eintrag der Werks-Bibliothek über Kategorie und Namen.
    public func factoryItem(category: String, name: String) -> SampleLibraryItem? {
        collections.first { $0.isFactory && $0.name.hasSuffix(category) }?.items.first { $0.name == name }
    }

    public func renameItem(_ id: UUID, to name: String) throws {
        for c in collections.indices {
            if let i = collections[c].items.firstIndex(where: { $0.id == id }) {
                collections[c].items[i].name = name
                try save()
                return
            }
        }
    }

    public func removeItem(_ id: UUID, deleteFile: Bool) throws {
        for c in collections.indices {
            if let i = collections[c].items.firstIndex(where: { $0.id == id }) {
                let item = collections[c].items.remove(at: i)
                if deleteFile, item.relativePath != nil, let url = url(for: item) {
                    try? FileManager.default.removeItem(at: url)
                }
                try save()
                return
            }
        }
    }

    public func item(withID id: UUID) -> SampleLibraryItem? {
        for c in collections { if let i = c.items.first(where: { $0.id == id }) { return i } }
        return nil
    }

    public func url(for item: SampleLibraryItem) -> URL? {
        if let rel = item.relativePath { return root.appendingPathComponent(rel) }
        if let abs = item.absolutePath { return URL(fileURLWithPath: abs) }
        return nil
    }

    public func url(forItemID id: UUID) -> URL? {
        item(withID: id).flatMap { url(for: $0) }
    }
}
