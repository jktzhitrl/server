import Foundation

/// Herkunft der Audiodaten eines Pads beim Speichern.
public enum PadSampleSource {
    case none
    /// Vorhandene Datei, die in das Paket kopiert wird (Originalformat bleibt erhalten)
    case file(URL)
    /// Audiodaten im Speicher (z. B. Werks-Kit), werden als 32-Bit-Float-WAV geschrieben
    case buffer(SampleBuffer)
}

/// Gemeinsame Logik für Projekt- und Kit-Pakete: kopiert bzw. schreibt alle Samples in
/// den Unterordner `Samples/` und erzeugt passende `SampleReference`s.
enum SamplePackager {
    static let samplesFolder = "Samples"

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sample" : String(cleaned.prefix(80))
    }

    /// Schreibt die Samples und liefert die aktualisierten Pad-Konfigurationen.
    static func writeSamples(pads: [PadConfig], sources: [PadSampleSource], into folder: URL) throws -> [PadConfig] {
        let fm = FileManager.default
        let samplesURL = folder.appendingPathComponent(samplesFolder, isDirectory: true)
        try fm.createDirectory(at: samplesURL, withIntermediateDirectories: true)
        var result = pads
        for i in result.indices {
            let source = sources.indices.contains(i) ? sources[i] : .none
            let prefix = String(format: "%02d-", i + 1)
            switch source {
            case .none:
                result[i].sample = nil
            case .file(let url):
                let fileName = prefix + sanitize(url.deletingPathExtension().lastPathComponent) + "." + (url.pathExtension.isEmpty ? "wav" : url.pathExtension)
                let dest = samplesURL.appendingPathComponent(fileName)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: url, to: dest)
                var ref = result[i].sample ?? SampleReference(fileName: url.lastPathComponent)
                ref.packagePath = samplesFolder + "/" + fileName
                if ref.originalPath == nil { ref.originalPath = url.path }
                ref.fileSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value
                result[i].sample = ref
            case .buffer(let buffer):
                let fileName = prefix + sanitize(buffer.name) + ".wav"
                let dest = samplesURL.appendingPathComponent(fileName)
                let data = buffer.channelData()
                let left = data[0]
                let right = data.count > 1 ? data[1] : data[0]
                try AudioFileWriter.write(left: left, right: right, sampleRate: buffer.sampleRate,
                                          format: .wav, bitDepth: .float32, to: dest, dither: false)
                var ref = result[i].sample ?? SampleReference(fileName: fileName)
                ref.fileName = ref.fileName.isEmpty ? fileName : ref.fileName
                ref.packagePath = samplesFolder + "/" + fileName
                ref.frameCount = buffer.frameCount
                ref.sampleRate = buffer.sampleRate
                ref.fileSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value
                result[i].sample = ref
            }
        }
        return result
    }

    /// Ersetzt `destination` atomar durch `staging` (Sicherung wird bei Erfolg gelöscht).
    static func replace(_ destination: URL, with staging: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            let backup = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).backup-\(UUID().uuidString)")
            try fm.moveItem(at: destination, to: backup)
            do {
                try fm.moveItem(at: staging, to: destination)
            } catch {
                try? fm.moveItem(at: backup, to: destination)
                throw error
            }
            try? fm.removeItem(at: backup)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
    }

    static func stagingURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).saving-\(UUID().uuidString)", isDirectory: true)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        e.dataEncodingStrategy = .base64
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.dataDecodingStrategy = .base64
        return d
    }
}
