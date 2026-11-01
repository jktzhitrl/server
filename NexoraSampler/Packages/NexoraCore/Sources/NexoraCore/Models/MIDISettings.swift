import Foundation

/// Zuordnung eines MIDI-Controllers (CC) zu einem Parameter.
public struct MIDICCMapping: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// 0 = alle Kanäle, sonst 1 ... 16
    public var channel: Int
    /// Controller-Nummer 0 ... 127
    public var controller: Int
    public var parameter: ParameterID
    /// Fester Pad-Bezug für Pad-Parameter; `nil` = jeweils ausgewähltes Pad
    public var padIndex: Int?

    public init(channel: Int, controller: Int, parameter: ParameterID, padIndex: Int? = nil) {
        id = UUID()
        self.channel = channel
        self.controller = controller
        self.parameter = parameter
        self.padIndex = padIndex
    }
}

public struct MIDISettings: Codable, Equatable, Sendable {
    public static let defaultBaseNote = 36

    /// 0 = Omni (alle Kanäle), sonst 1 ... 16
    public var inputChannel: Int = 0
    /// MIDI-Note je Pad (Standard: C1 = 36 … D#2 = 51, kompatibel zu gängigen Pad-Controllern)
    public var padNotes: [Int] = (0..<16).map { MIDISettings.defaultBaseNote + $0 }
    public var ccMappings: [MIDICCMapping] = []
    /// MIDI Start/Stop/Continue steuert den Transport
    public var respondToTransport: Bool = true
    /// Anschlagstärke ignorieren (immer volle Lautstärke)
    public var fixedVelocity: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputChannel = DSP.clamp(c.value(.inputChannel, default: 0), 0, 16)
        padNotes = c.value(.padNotes, default: (0..<16).map { MIDISettings.defaultBaseNote + $0 })
        ccMappings = c.value(.ccMappings, default: [])
        respondToTransport = c.value(.respondToTransport, default: true)
        fixedVelocity = c.value(.fixedVelocity, default: false)
        normalize()
    }

    public mutating func normalize() {
        var notes = Array(padNotes.prefix(16))
        while notes.count < 16 { notes.append(Self.defaultBaseNote + notes.count) }
        padNotes = notes.map { DSP.clamp($0, 0, 127) }
        ccMappings = ccMappings.filter { (0...127).contains($0.controller) && (0...16).contains($0.channel) }
    }

    /// Pad-Index für eine eingehende Note (erste Übereinstimmung).
    public func pad(forNote note: Int) -> Int? {
        padNotes.firstIndex(of: note)
    }

    public func accepts(channel: Int) -> Bool {
        inputChannel == 0 || inputChannel == channel
    }

    /// Alle Mappings, die auf einen eingehenden Controller reagieren.
    public func mappings(controller: Int, channel: Int) -> [MIDICCMapping] {
        ccMappings.filter { $0.controller == controller && ($0.channel == 0 || $0.channel == channel) }
    }

    /// Fügt ein Mapping hinzu und entfernt dabei Konflikte (gleicher Controller/Kanal
    /// oder gleicher Parameter mit gleichem Pad-Bezug) – Verhalten von MIDI-Learn.
    public mutating func learn(controller: Int, channel: Int, parameter: ParameterID, padIndex: Int? = nil) {
        ccMappings.removeAll {
            ($0.controller == controller && $0.channel == channel) ||
            ($0.parameter == parameter && $0.padIndex == padIndex)
        }
        ccMappings.append(MIDICCMapping(channel: channel, controller: controller, parameter: parameter, padIndex: padIndex))
    }

    public mutating func removeMappings(for parameter: ParameterID) {
        ccMappings.removeAll { $0.parameter == parameter }
    }

    public func mapping(for parameter: ParameterID) -> MIDICCMapping? {
        ccMappings.first { $0.parameter == parameter }
    }
}
