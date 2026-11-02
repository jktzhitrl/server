import Foundation

/// Verweis auf eine Sample-Datei. Mehrere Fundorte werden gespeichert, damit Samples
/// beim erneuten Öffnen zuverlässig gefunden werden (siehe `SampleResolver`).
public struct SampleReference: Codable, Equatable, Sendable {
    /// Ursprünglicher Dateiname inkl. Endung
    public var fileName: String
    /// Pfad relativ zum Projekt-Paket (z. B. "Samples/01-Kick.wav") – primärer Fundort
    public var packagePath: String?
    /// Absoluter Pfad der Originaldatei zum Zeitpunkt des Imports
    public var originalPath: String?
    /// macOS-Lesezeichen (Bookmark) der Originaldatei – überlebt Umbenennen/Verschieben
    public var bookmark: Data?
    /// Eintrag in der Sample-Bibliothek, falls von dort geladen
    public var libraryItemID: UUID?
    /// Metadaten zur Plausibilitätsprüfung bei der Suche
    public var fileSize: Int64?
    public var frameCount: Int?
    public var sampleRate: Double?

    public init(fileName: String, packagePath: String? = nil, originalPath: String? = nil,
                bookmark: Data? = nil, libraryItemID: UUID? = nil, fileSize: Int64? = nil,
                frameCount: Int? = nil, sampleRate: Double? = nil) {
        self.fileName = fileName
        self.packagePath = packagePath
        self.originalPath = originalPath
        self.bookmark = bookmark
        self.libraryItemID = libraryItemID
        self.fileSize = fileSize
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }
}

/// Belegung eines Pads.
public struct PadConfig: Codable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var sample: SampleReference?
    public var settings: PadSettings
    /// Tastaturtaste (ein Zeichen) zum Auslösen
    public var keyboardKey: String

    public init(index: Int, name: String, sample: SampleReference? = nil,
                settings: PadSettings = PadSettings(), keyboardKey: String? = nil) {
        self.index = index
        self.name = name
        self.sample = sample
        self.settings = settings
        self.keyboardKey = keyboardKey ?? PadConfig.defaultKey(for: index)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = DSP.clamp(c.value(.index, default: 0), 0, 15)
        name = c.value(.name, default: "PAD \(index + 1)")
        sample = c.value(.sample, default: nil)
        settings = c.value(.settings, default: PadSettings())
        keyboardKey = c.value(.keyboardKey, default: PadConfig.defaultKey(for: index))
    }

    /// Standard-Tastenbelegung passend zum 2×8-Pad-Feld:
    /// obere Pad-Reihe (Pads 1–8) = `Q W E R T Y U I`, untere Reihe (Pads 9–16) = `A S D F G H J K`.
    public static let defaultKeys: [String] = [
        "q", "w", "e", "r", "t", "y", "u", "i",
        "a", "s", "d", "f", "g", "h", "j", "k"
    ]

    public static func defaultKey(for index: Int) -> String {
        defaultKeys.indices.contains(index) ? defaultKeys[index] : ""
    }
}

/// Quantisierung bei der Live-Aufnahme.
public enum QuantizeMode: String, Codable, CaseIterable, Sendable {
    case off, sixteenth, eighth, quarter

    public var shortName: String {
        switch self {
        case .off: return "OFF"
        case .sixteenth: return "1/16"
        case .eighth: return "1/8"
        case .quarter: return "1/4"
        }
    }

    /// Rasterweite in Sequencer-Schritten (16tel); `nil` = keine Quantisierung.
    public var gridSteps: Int? {
        switch self {
        case .off: return nil
        case .sixteenth: return 1
        case .eighth: return 2
        case .quarter: return 4
        }
    }
}

/// Zustand des Step-Sequencers.
public struct SequencerState: Codable, Equatable, Sendable {
    public static let patternSlots = 8

    public var patterns: [SequencerPattern]
    public var currentPattern: Int = 0
    public var quantize: QuantizeMode = .sixteenth
    public var metronome: Bool = false
    /// Pattern-Wechsel erst am Taktende (wie bei Hardware) statt sofort
    public var switchAtBarEnd: Bool = true
    public var trackMutes: [Bool] = Array(repeating: false, count: SequencerPattern.trackCount)
    public var trackSolos: [Bool] = Array(repeating: false, count: SequencerPattern.trackCount)
    /// Wiedergabe der Motion-Spuren
    public var motionMode: MotionMode = .hold
    /// Song-Modus: Patterns laufen in der Reihenfolge von `ProjectDocument.patternChain`
    public var songMode: Bool = false

    public init() {
        patterns = (0..<Self.patternSlots).map { SequencerPattern(name: "Pattern \(Self.slotName($0))") }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patterns = c.value(.patterns, default: [])
        currentPattern = c.value(.currentPattern, default: 0)
        quantize = c.value(.quantize, default: .sixteenth)
        metronome = c.value(.metronome, default: false)
        switchAtBarEnd = c.value(.switchAtBarEnd, default: true)
        trackMutes = c.value(.trackMutes, default: [])
        trackSolos = c.value(.trackSolos, default: [])
        motionMode = c.value(.motionMode, default: .hold)
        songMode = c.value(.songMode, default: false)
        normalize()
    }

    public mutating func normalize() {
        if patterns.count > Self.patternSlots { patterns = Array(patterns.prefix(Self.patternSlots)) }
        while patterns.count < Self.patternSlots {
            patterns.append(SequencerPattern(name: "Pattern \(Self.slotName(patterns.count))"))
        }
        for i in patterns.indices { patterns[i].normalize() }
        currentPattern = DSP.clamp(currentPattern, 0, Self.patternSlots - 1)
        trackMutes = Self.normalizedFlags(trackMutes)
        trackSolos = Self.normalizedFlags(trackSolos)
    }

    private static func normalizedFlags(_ flags: [Bool]) -> [Bool] {
        var f = Array(flags.prefix(SequencerPattern.trackCount))
        while f.count < SequencerPattern.trackCount { f.append(false) }
        return f
    }

    public static func slotName(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOP")
        return letters.indices.contains(index) ? String(letters[index]) : "\(index + 1)"
    }

    public var muteMask: UInt16 { Self.mask(trackMutes) }
    public var soloMask: UInt16 { Self.mask(trackSolos) }

    private static func mask(_ flags: [Bool]) -> UInt16 {
        var m: UInt16 = 0
        for (i, f) in flags.enumerated() where f && i < 16 { m |= (1 << UInt16(i)) }
        return m
    }
}

/// Zuweisung der XY-Pad-Achsen.
public struct XYPadAssignment: Codable, Equatable, Sendable {
    public var xParameter: ParameterID = .masterFilterCutoff
    public var yParameter: ParameterID = .reverbMix

    public init(x: ParameterID = .masterFilterCutoff, y: ParameterID = .reverbMix) {
        xParameter = x
        yParameter = y
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xParameter = c.value(.xParameter, default: .masterFilterCutoff)
        yParameter = c.value(.yParameter, default: .reverbMix)
    }
}

/// Audio-Exportformat.
public enum ExportFileFormat: String, Codable, CaseIterable, Sendable {
    case wav, aiff
    public var fileExtension: String { self == .wav ? "wav" : "aif" }
}

public enum ExportBitDepth: String, Codable, CaseIterable, Sendable {
    case pcm16, pcm24, float32

    public var displayName: String {
        switch self {
        case .pcm16: return "16 Bit"
        case .pcm24: return "24 Bit"
        case .float32: return "32 Bit Float"
        }
    }
}

public struct ExportSettings: Codable, Equatable, Sendable {
    public var format: ExportFileFormat = .wav
    public var sampleRate: Double = 44_100
    public var bitDepth: ExportBitDepth = .pcm24
    /// Wiederholungen jedes Patterns
    public var loops: Int = 2
    /// Maximale Ausklingzeit (Hall/Delay) in Sekunden
    public var tailSeconds: Double = 3
    /// Exportiert die Pattern-Kette statt nur des aktuellen Patterns
    public var exportChain: Bool = false
    public var normalize: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.value(.format, default: .wav)
        sampleRate = c.value(.sampleRate, default: 44_100)
        bitDepth = c.value(.bitDepth, default: .pcm24)
        loops = DSP.clamp(c.value(.loops, default: 2), 1, 64)
        tailSeconds = DSP.clamp(c.value(.tailSeconds, default: 3), 0, 30)
        exportChain = c.value(.exportChain, default: false)
        normalize = c.value(.normalize, default: false)
    }
}

/// Wurzelobjekt einer Projektdatei (`project.json` im `.nexora`-Paket).
/// Das Format ist in `docs/PROJECT_FORMAT.md` dokumentiert.
public struct ProjectDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let formatIdentifier = "de.nexora.sampler.project"

    public var format: String = ProjectDocument.formatIdentifier
    public var formatVersion: Int = ProjectDocument.currentFormatVersion
    public var name: String
    public var kitName: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// 40 ... 300
    public var bpm: Double = 120
    /// 50 ... 75 (%)
    public var swing: Double = 50
    public var pads: [PadConfig]
    public var master: MasterSettings
    public var engine: EngineSettings
    public var sequencer: SequencerState
    public var xyPad: XYPadAssignment
    public var midi: MIDISettings
    public var export: ExportSettings
    /// Reihenfolge der Patterns für Song-Modus und Ketten-Export (Slot-Indizes, max. 64)
    public var patternChain: [Int]

    public init(name: String = "Untitled") {
        self.name = name
        kitName = "Empty Kit"
        createdAt = Date()
        modifiedAt = Date()
        pads = (0..<16).map { PadConfig(index: $0, name: "PAD \($0 + 1)") }
        master = MasterSettings()
        engine = EngineSettings()
        sequencer = SequencerState()
        xyPad = XYPadAssignment()
        midi = MIDISettings()
        export = ExportSettings()
        patternChain = [0]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = c.value(.formatVersion, default: 1)
        if version > Self.currentFormatVersion {
            throw ProjectError.unsupportedVersion(version)
        }
        format = c.value(.format, default: Self.formatIdentifier)
        formatVersion = version
        name = c.value(.name, default: "Untitled")
        kitName = c.value(.kitName, default: "Kit")
        createdAt = c.value(.createdAt, default: Date())
        modifiedAt = c.value(.modifiedAt, default: Date())
        bpm = DSP.clamp(c.value(.bpm, default: 120), 40, 300)
        swing = DSP.clamp(c.value(.swing, default: 50), 50, 75)
        pads = c.value(.pads, default: [])
        master = c.value(.master, default: MasterSettings())
        engine = c.value(.engine, default: EngineSettings())
        sequencer = c.value(.sequencer, default: SequencerState())
        xyPad = c.value(.xyPad, default: XYPadAssignment())
        midi = c.value(.midi, default: MIDISettings())
        export = c.value(.export, default: ExportSettings())
        patternChain = c.value(.patternChain, default: [0])
        normalize()
    }

    /// Repariert unvollständige Daten (fehlende Pads, ungültige Indizes).
    public mutating func normalize() {
        var byIndex: [Int: PadConfig] = [:]
        for pad in pads where (0..<16).contains(pad.index) { byIndex[pad.index] = pad }
        pads = (0..<16).map { byIndex[$0] ?? PadConfig(index: $0, name: "PAD \($0 + 1)") }
        sequencer.normalize()
        midi.normalize()
        patternChain = Array(patternChain.filter { (0..<SequencerState.patternSlots).contains($0) }.prefix(64))
        if patternChain.isEmpty { patternChain = [sequencer.currentPattern] }
    }

    public var currentPattern: SequencerPattern {
        get { sequencer.patterns[sequencer.currentPattern] }
        set { sequencer.patterns[sequencer.currentPattern] = newValue }
    }
}

public enum ProjectError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case missingManifest
    case invalidPackage(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Die Projektdatei wurde mit einer neueren Version erstellt (Format \(v))."
        case .missingManifest:
            return "Im Projektordner fehlt die Datei project.json."
        case .invalidPackage(let reason):
            return "Ungültiges Projekt: \(reason)"
        }
    }
}
