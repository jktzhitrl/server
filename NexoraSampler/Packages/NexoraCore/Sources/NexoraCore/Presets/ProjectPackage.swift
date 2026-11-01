import Foundation

/// Lesen und Schreiben von Projekt-Paketen.
///
/// Ein Projekt ist ein Ordner mit der Endung `.nexora` (unter macOS als Dokumentpaket registriert):
/// ```
/// MeinBeat.nexora/
///   project.json      – ProjectDocument (JSON, UTF-8)
///   Samples/          – Kopien aller verwendeten Samples
///     01-Kick.wav
///     02-Snare.aif …
/// ```
/// Da alle Samples im Paket liegen, ist ein Projekt in sich geschlossen und kann
/// verschoben, kopiert oder weitergegeben werden.
public enum ProjectPackage {
    public static let fileExtension = "nexora"
    public static let manifestName = "project.json"

    /// Speichert das Projekt. Vorhandene Pakete werden erst nach erfolgreichem Schreiben ersetzt.
    /// - Returns: Das gespeicherte Dokument mit aktualisierten Sample-Verweisen.
    @discardableResult
    public static func write(_ document: ProjectDocument, sources: [PadSampleSource], to packageURL: URL) throws -> ProjectDocument {
        let fm = FileManager.default
        let staging = SamplePackager.stagingURL(for: packageURL)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var doc = document
            doc.modifiedAt = Date()
            doc.formatVersion = ProjectDocument.currentFormatVersion
            doc.format = ProjectDocument.formatIdentifier
            doc.pads = try SamplePackager.writeSamples(pads: doc.pads, sources: sources, into: staging)
            let data = try SamplePackager.encoder.encode(doc)
            try data.write(to: staging.appendingPathComponent(manifestName), options: .atomic)
            try SamplePackager.replace(packageURL, with: staging)
            return doc
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Liest ein Projekt. Akzeptiert den Paketordner oder direkt die `project.json`.
    public static func read(from url: URL) throws -> ProjectDocument {
        let manifest = manifestURL(for: url)
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw ProjectError.missingManifest }
        let data = try Data(contentsOf: manifest)
        var doc = try SamplePackager.decoder.decode(ProjectDocument.self, from: data)
        doc.normalize()
        return doc
    }

    public static func manifestURL(for url: URL) -> URL {
        url.lastPathComponent == manifestName ? url : url.appendingPathComponent(manifestName)
    }

    /// Paketordner zu einer URL (Paket selbst oder enthaltene project.json).
    public static func packageURL(for url: URL) -> URL {
        url.lastPathComponent == manifestName ? url.deletingLastPathComponent() : url
    }

    public static func isProjectPackage(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(for: url).path)
    }
}
