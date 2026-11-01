import Foundation

/// Findet die Audiodatei zu einer `SampleReference`.
///
/// Suchreihenfolge:
/// 1. Kopie im Projekt-/Kit-Paket (`packagePath`)
/// 2. Eintrag in der Sample-Bibliothek (`libraryItemID`)
/// 3. macOS-Bookmark (findet auch umbenannte/verschobene Dateien)
/// 4. Ursprünglicher absoluter Pfad
/// 5. Suche nach Dateiname in den Suchordnern (bevorzugt mit gleicher Dateigröße)
public struct SampleResolver {
    public var searchDirectories: [URL]
    public var bookmarkResolver: ((Data) -> URL?)?
    public var libraryLookup: ((UUID) -> URL?)?
    public var maximumSearchDepth: Int

    public init(searchDirectories: [URL] = [], bookmarkResolver: ((Data) -> URL?)? = nil,
                libraryLookup: ((UUID) -> URL?)? = nil, maximumSearchDepth: Int = 6) {
        self.searchDirectories = searchDirectories
        self.bookmarkResolver = bookmarkResolver
        self.libraryLookup = libraryLookup
        self.maximumSearchDepth = maximumSearchDepth
    }

    public enum Location: Equatable {
        case package, library, bookmark, originalPath, search
    }

    public func resolve(_ reference: SampleReference, packageURL: URL?) -> URL? {
        resolveWithLocation(reference, packageURL: packageURL)?.url
    }

    public func resolveWithLocation(_ reference: SampleReference, packageURL: URL?) -> (url: URL, location: Location)? {
        let fm = FileManager.default
        func exists(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        if let packageURL, let rel = reference.packagePath {
            let url = packageURL.appendingPathComponent(rel)
            if exists(url) { return (url, .package) }
        }
        if let id = reference.libraryItemID, let url = libraryLookup?(id), exists(url) {
            return (url, .library)
        }
        if let bookmark = reference.bookmark, let url = bookmarkResolver?(bookmark), exists(url) {
            return (url, .bookmark)
        }
        if let path = reference.originalPath {
            let url = URL(fileURLWithPath: path)
            if exists(url) { return (url, .originalPath) }
        }
        let wanted = reference.fileName.lowercased()
        guard !wanted.isEmpty else { return nil }
        var candidates: [URL] = []
        for dir in searchDirectories {
            candidates.append(contentsOf: findFiles(named: wanted, in: dir))
        }
        if let size = reference.fileSize,
           let exact = candidates.first(where: { fileSize($0) == size }) {
            return (exact, .search)
        }
        if let first = candidates.first { return (first, .search) }
        return nil
    }

    private func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private func findFiles(named lowercasedName: String, in directory: URL) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        var queue: [(URL, Int)] = [(directory, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if depth < maximumSearchDepth && !item.lastPathComponent.hasPrefix(".") { queue.append((item, depth + 1)) }
                } else if item.lastPathComponent.lowercased() == lowercasedName {
                    result.append(item)
                }
            }
        }
        return result
    }
}
