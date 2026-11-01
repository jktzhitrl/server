import Foundation
import Observation
import AVFoundation
import NexoraCore

/// Beobachtbare Hülle um `SampleLibrary` für den Sample-Browser.
@MainActor
@Observable
final class LibraryModel {
    @ObservationIgnored let library: SampleLibrary
    private(set) var collections: [SampleLibraryCollection]
    var selectedCollectionID: UUID?
    var selectedItemID: UUID?
    var searchText = ""
    /// Während die Werks-Bibliothek installiert wird, sind Änderungen gesperrt.
    var isBusy = false

    init(root: URL) {
        library = SampleLibrary(root: root)
        collections = library.collections
        selectedCollectionID = library.collections.first?.id
    }

    var root: URL { library.root }

    var selectedCollection: SampleLibraryCollection? {
        collections.first { $0.id == selectedCollectionID } ?? collections.first
    }

    /// Einträge der ausgewählten Sammlung – bei aktiver Suche aus allen Sammlungen.
    var visibleItems: [SampleLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return selectedCollection?.items ?? [] }
        return collections.flatMap(\.items).filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var factoryCollections: [SampleLibraryCollection] { collections.filter(\.isFactory) }
    var userCollections: [SampleLibraryCollection] { collections.filter { !$0.isFactory } }

    func collectionName(for item: SampleLibraryItem) -> String {
        collections.first { $0.items.contains { $0.id == item.id } }?.name ?? ""
    }

    func reload() {
        refresh()
    }

    private func checkNotBusy() throws {
        if isBusy { throw ProjectError.invalidPackage("Die Werks-Bibliothek wird gerade eingerichtet – bitte kurz warten.") }
    }

    private func refresh() {
        collections = library.collections
        if selectedCollectionID == nil || !collections.contains(where: { $0.id == selectedCollectionID }) {
            selectedCollectionID = collections.first?.id
        }
    }

    func createCollection(named name: String) throws {
        try checkNotBusy()
        let c = try library.createCollection(name: name)
        refresh()
        selectedCollectionID = c.id
    }

    func renameCollection(_ id: UUID, to name: String) throws {
        try checkNotBusy()
        try library.renameCollection(id, to: name)
        refresh()
    }

    func removeCollection(_ id: UUID) throws {
        try checkNotBusy()
        try library.removeCollection(id, deleteFiles: true)
        refresh()
    }

    /// Importiert Audiodateien in die ausgewählte Bibliothek. Liefert die neuen Einträge.
    @discardableResult
    func importFiles(_ urls: [URL], copy: Bool) -> (imported: [SampleLibraryItem], failed: [String]) {
        guard !isBusy else { return ([], urls.map(\.lastPathComponent)) }
        // Importe landen nie in einer Werks-Sammlung.
        let targetCollection = (selectedCollection?.isFactory == false ? selectedCollection : userCollections.first)
        guard let target = targetCollection?.id else { return ([], urls.map(\.lastPathComponent)) }
        var imported: [SampleLibraryItem] = []
        var failed: [String] = []
        for url in urls {
            guard AudioFileLoader.isSupported(url), let info = Self.audioInfo(url) else {
                failed.append(url.lastPathComponent)
                continue
            }
            do {
                imported.append(try library.importFile(url, into: target, copy: copy,
                                                       duration: info.duration, sampleRate: info.sampleRate, channels: info.channels))
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        refresh()
        return (imported, failed)
    }

    func renameItem(_ id: UUID, to name: String) throws {
        try checkNotBusy()
        try library.renameItem(id, to: name)
        refresh()
    }

    func removeItem(_ id: UUID) throws {
        try checkNotBusy()
        try library.removeItem(id, deleteFile: true)
        if selectedItemID == id { selectedItemID = nil }
        refresh()
    }

    func url(for item: SampleLibraryItem) -> URL? { library.url(for: item) }
    func url(forItemID id: UUID) -> URL? { library.url(forItemID: id) }

    /// Liest Dauer, Abtastrate und Kanalzahl aus dem Dateikopf (ohne vollständiges Dekodieren).
    static func audioInfo(_ url: URL) -> (duration: Double, sampleRate: Double, channels: Int)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.fileFormat
        guard format.sampleRate > 0 else { return nil }
        return (Double(file.length) / format.sampleRate, format.sampleRate, Int(format.channelCount))
    }
}
