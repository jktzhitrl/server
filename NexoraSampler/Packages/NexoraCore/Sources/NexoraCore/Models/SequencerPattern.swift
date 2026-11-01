import Foundation

/// Ein einzelner Sequencer-Schritt.
public struct SequencerStep: Codable, Equatable, Hashable, Sendable {
    public var active: Bool = false
    /// Anschlagstärke 0 ... 1
    public var velocity: Double = 0.8
    /// Mikro-Timing relativ zum Raster in Schritten (-0.5 ..< 0.5); 0 = exakt quantisiert
    public var offset: Double = 0

    public init(active: Bool = false, velocity: Double = 0.8, offset: Double = 0) {
        self.active = active
        self.velocity = velocity
        self.offset = offset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.value(.active, default: false)
        velocity = DSP.clamp(c.value(.velocity, default: 0.8), 0, 1)
        offset = DSP.clamp(c.value(.offset, default: 0), -0.5, 0.499)
    }
}

/// Ein SequencerPattern: 16 Spuren (eine je Pad) × bis zu 16 Schritte.
public struct SequencerPattern: Codable, Equatable, Identifiable, Sendable {
    public static let trackCount = 16
    public static let maxSteps = 16

    public var id: UUID
    public var name: String
    /// Anzahl aktiver Schritte (1 ... 16)
    public var length: Int
    /// `steps[track][step]`
    public var steps: [[SequencerStep]]
    /// Notenlänge je Spur in Schritten (relevant für Pads im Gate-/Loop-Modus)
    public var gates: [Double]

    public init(name: String, length: Int = 16) {
        id = UUID()
        self.name = name
        self.length = DSP.clamp(length, 1, Self.maxSteps)
        steps = Array(repeating: Array(repeating: SequencerStep(), count: Self.maxSteps), count: Self.trackCount)
        gates = Array(repeating: 1, count: Self.trackCount)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Pattern")
        length = DSP.clamp(c.value(.length, default: 16), 1, Self.maxSteps)
        steps = c.value(.steps, default: [])
        gates = c.value(.gates, default: [])
        normalize()
    }

    /// Stellt sicher, dass alle Dimensionen vollständig sind (robust gegen beschädigte Dateien).
    public mutating func normalize() {
        if steps.count > Self.trackCount { steps = Array(steps.prefix(Self.trackCount)) }
        while steps.count < Self.trackCount { steps.append([]) }
        for t in 0..<Self.trackCount {
            if steps[t].count > Self.maxSteps { steps[t] = Array(steps[t].prefix(Self.maxSteps)) }
            while steps[t].count < Self.maxSteps { steps[t].append(SequencerStep()) }
        }
        if gates.count > Self.trackCount { gates = Array(gates.prefix(Self.trackCount)) }
        while gates.count < Self.trackCount { gates.append(1) }
        gates = gates.map { DSP.clamp($0, 0.05, 16) }
    }

    public subscript(track: Int, step: Int) -> SequencerStep {
        get { steps[track][step] }
        set { steps[track][step] = newValue }
    }

    public mutating func toggle(track: Int, step: Int, velocity: Double = 0.8) {
        if steps[track][step].active {
            steps[track][step].active = false
        } else {
            steps[track][step] = SequencerStep(active: true, velocity: velocity, offset: 0)
        }
    }

    public mutating func clear() {
        for t in 0..<Self.trackCount { clearTrack(t) }
    }

    public mutating func clearTrack(_ track: Int) {
        steps[track] = Array(repeating: SequencerStep(), count: Self.maxSteps)
    }

    public var isEmpty: Bool { !steps.contains { $0.contains { $0.active } } }

    public func activeStepCount(track: Int) -> Int {
        steps[track].prefix(length).filter(\.active).count
    }
}

/// Unveränderliche, kompakte Kopie eines Patterns für den Audio-Thread.
public final class PatternSnapshot {
    public let length: Int
    /// Flaches Feld `track * maxSteps + step`
    public let steps: [SequencerStep]
    public let gates: [Double]

    public init(_ pattern: SequencerPattern) {
        var p = pattern
        p.normalize()
        length = p.length
        steps = p.steps.flatMap { $0 }
        gates = p.gates
    }

    @inline(__always)
    public func step(track: Int, step: Int) -> SequencerStep {
        steps[track * SequencerPattern.maxSteps + step]
    }
}
