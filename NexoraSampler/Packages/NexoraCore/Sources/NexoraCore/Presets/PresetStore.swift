import Foundation

/// Drum-Kit-Preset: Pad-Belegungen inkl. Samples und Pad-Einstellungen.
/// Gespeichert als Paket `Name.nexorakit/` mit `kit.json` und `Samples/`.
public struct KitPreset: Codable, Equatable, Sendable {
    public static let formatIdentifier = "de.nexora.sampler.kit"
    public var format = KitPreset.formatIdentifier
    public var formatVersion = 1
    public var name: String
    public var pads: [PadConfig]

    public init(name: String, pads: [PadConfig]) {
        self.name = name
        self.pads = pads
    }
}

/// Effekt-Preset: Einstellungen der Master-Effektkette (`Name.nexorafx`, JSON).
public struct EffectPreset: Codable, Equatable, Sendable {
    public static let formatIdentifier = "de.nexora.sampler.effects"
    public var format = EffectPreset.formatIdentifier
    public var formatVersion = 1
    public var name: String
    public var master: MasterSettings

    public init(name: String, master: MasterSettings) {
        self.name = name
        self.master = master
    }
}

/// Pattern-Preset: ein Sequencer-Pattern samt Tempo (`Name.nexorapattern`, JSON).
public struct PatternPreset: Codable, Equatable, Sendable {
    public static let formatIdentifier = "de.nexora.sampler.pattern"
    public var format = PatternPreset.formatIdentifier
    public var formatVersion = 1
    public var name: String
    public var pattern: SequencerPattern
    public var bpm: Double
    public var swing: Double

    public init(name: String, pattern: SequencerPattern, bpm: Double, swing: Double) {
        self.name = name
        self.pattern = pattern
        self.bpm = bpm
        self.swing = swing
    }
}

public struct PresetInfo: Identifiable, Equatable, Sendable {
    public var id: URL { url }
    public let name: String
    public let url: URL
    public let kind: PresetStore.Kind
    public let modified: Date
}

/// Verwaltet Presets im Benutzerordner (`~/Library/Application Support/NEXORA Sampler/Presets`).
public final class PresetStore {
    public enum Kind: String, CaseIterable, Sendable {
        case kit = "Kits"
        case effects = "Effects"
        case pattern = "Patterns"

        public var fileExtension: String {
            switch self {
            case .kit: return "nexorakit"
            case .effects: return "nexorafx"
            case .pattern: return "nexorapattern"
            }
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
        for kind in Kind.allCases {
            try? FileManager.default.createDirectory(at: folder(for: kind), withIntermediateDirectories: true)
        }
    }

    public func folder(for kind: Kind) -> URL {
        root.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    public func url(for name: String, kind: Kind) -> URL {
        folder(for: kind).appendingPathComponent(SamplePackager.sanitize(name) + "." + kind.fileExtension)
    }

    public func list(_ kind: Kind) -> [PresetInfo] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder(for: kind), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { $0.pathExtension == kind.fileExtension }
            .map { url in
                let date = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date.distantPast
                return PresetInfo(name: url.deletingPathExtension().lastPathComponent, url: url, kind: kind, modified: date)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func delete(_ preset: PresetInfo) throws {
        try FileManager.default.removeItem(at: preset.url)
    }

    // MARK: Kits

    @discardableResult
    public func saveKit(name: String, pads: [PadConfig], sources: [PadSampleSource], to explicitURL: URL? = nil) throws -> URL {
        let destination = explicitURL ?? url(for: name, kind: .kit)
        let staging = SamplePackager.stagingURL(for: destination)
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let packaged = try SamplePackager.writeSamples(pads: pads, sources: sources, into: staging)
            let kit = KitPreset(name: name, pads: packaged)
            try SamplePackager.encoder.encode(kit).write(to: staging.appendingPathComponent("kit.json"), options: .atomic)
            try SamplePackager.replace(destination, with: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return destination
    }

    public func loadKit(at url: URL) throws -> KitPreset {
        let data = try Data(contentsOf: url.appendingPathComponent("kit.json"))
        var kit = try SamplePackager.decoder.decode(KitPreset.self, from: data)
        var doc = ProjectDocument()
        doc.pads = kit.pads
        doc.normalize()
        kit.pads = doc.pads
        return kit
    }

    // MARK: Effekte

    @discardableResult
    public func saveEffects(name: String, master: MasterSettings) throws -> URL {
        let destination = url(for: name, kind: .effects)
        try SamplePackager.encoder.encode(EffectPreset(name: name, master: master)).write(to: destination, options: .atomic)
        return destination
    }

    public func loadEffects(at url: URL) throws -> EffectPreset {
        try SamplePackager.decoder.decode(EffectPreset.self, from: Data(contentsOf: url))
    }

    // MARK: Patterns

    @discardableResult
    public func savePattern(name: String, pattern: SequencerPattern, bpm: Double, swing: Double) throws -> URL {
        let destination = url(for: name, kind: .pattern)
        var p = pattern
        p.name = name
        try SamplePackager.encoder.encode(PatternPreset(name: name, pattern: p, bpm: bpm, swing: swing))
            .write(to: destination, options: .atomic)
        return destination
    }

    public func loadPattern(at url: URL) throws -> PatternPreset {
        try SamplePackager.decoder.decode(PatternPreset.self, from: Data(contentsOf: url))
    }
}
