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

/// Wiedergabeart der Motion-Sequenz (aufgezeichnete Reglerbewegungen).
public enum MotionMode: String, Codable, CaseIterable, Sendable {
    /// Motion-Spuren werden ignoriert.
    case off
    /// Jeder Schritt hält seinen Wert bis zum nächsten Schritt (Stufen).
    case hold
    /// Werte werden zwischen den Schritten weich übergeblendet.
    case smooth

    public var displayName: String {
        switch self {
        case .off: return "AUS"
        case .hold: return "STUFEN"
        case .smooth: return "GLATT"
        }
    }
}

/// Eine Motion-Spur: aufgezeichnete Werte eines Parameters je Schritt.
public struct MotionLane: Codable, Equatable, Hashable, Sendable {
    /// Höchstzahl an Motion-Spuren je Pattern.
    public static let maxLanes = 24

    public var parameter: ParameterID
    /// Pad-Index (0 ... 15) bei Pad-Parametern, −1 bei Master-Parametern.
    public var pad: Int
    /// Tatsächliche Parameterwerte je Schritt; `nil` = kein Wert aufgezeichnet.
    public var values: [Double?]

    enum CodingKeys: String, CodingKey { case parameter, pad, values }

    public init(parameter: ParameterID, pad: Int) {
        self.parameter = parameter
        self.pad = parameter.isPadParameter ? DSP.clamp(pad, 0, 15) : -1
        values = Array(repeating: nil, count: SequencerPattern.maxSteps)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parameter = try c.decode(ParameterID.self, forKey: .parameter)
        let p = c.value(.pad, default: -1)
        pad = parameter.isPadParameter ? DSP.clamp(p, 0, 15) : -1
        values = c.value(.values, default: [])
        normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(parameter, forKey: .parameter)
        try c.encode(pad, forKey: .pad)
        let last = values.lastIndex { $0 != nil } ?? -1
        try c.encode(Array(values.prefix(last + 1)), forKey: .values)
    }

    mutating func normalize() {
        let spec = parameter.spec
        if values.count > SequencerPattern.maxSteps { values = Array(values.prefix(SequencerPattern.maxSteps)) }
        while values.count < SequencerPattern.maxSteps { values.append(nil) }
        values = values.map { $0.map { DSP.clamp($0, spec.minimum, spec.maximum) } }
    }

    /// Nur Pad- und Master-Parameter lassen sich aufzeichnen (Tempo/Swing nicht).
    public static func canRecord(_ id: ParameterID) -> Bool {
        id.padKeyPath != nil || id.masterKeyPath != nil
    }

    public func hasValues(length: Int) -> Bool {
        values.prefix(max(1, length)).contains { $0 != nil }
    }

    public var displayName: String {
        let name = parameter.spec.shortName
        return pad >= 0 ? "PAD \(String(format: "%02d", pad + 1)) \(name)" : "MASTER \(name)"
    }
}

/// Ein SequencerPattern: 16 Spuren (eine je Pad) × bis zu 64 Schritte (4 Takte).
public struct SequencerPattern: Codable, Equatable, Identifiable, Sendable {
    public static let trackCount = 16
    public static let maxSteps = 64
    /// Schritte je Seite in Raster und Step-Modus.
    public static let stepsPerPage = 16
    public static let pageCount = maxSteps / stepsPerPage

    public var id: UUID
    public var name: String
    /// Anzahl aktiver Schritte (1 ... 64)
    public var length: Int
    /// `steps[track][step]`
    public var steps: [[SequencerStep]]
    /// Notenlänge je Spur in Schritten (relevant für Pads im Gate-/Loop-Modus)
    public var gates: [Double]
    /// Aufgezeichnete Reglerbewegungen
    public var motion: [MotionLane]

    enum CodingKeys: String, CodingKey { case id, name, length, steps, gates, motion }

    public init(name: String, length: Int = 16) {
        id = UUID()
        self.name = name
        self.length = DSP.clamp(length, 1, Self.maxSteps)
        steps = Array(repeating: Array(repeating: SequencerStep(), count: Self.maxSteps), count: Self.trackCount)
        gates = Array(repeating: 1, count: Self.trackCount)
        motion = []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Pattern")
        length = DSP.clamp(c.value(.length, default: 16), 1, Self.maxSteps)
        steps = c.value(.steps, default: [])
        gates = c.value(.gates, default: [])
        motion = c.value(.motion, default: [])
        normalize()
    }

    /// Schreibt nur die belegten Seiten (mindestens die Pattern-Länge) – Dateien bleiben
    /// kompakt und ältere 16-Schritt-Versionen lesen die ersten 16 Schritte.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(length, forKey: .length)
        try c.encode(steps.map { Array($0.prefix(storedStepCount)) }, forKey: .steps)
        try c.encode(gates, forKey: .gates)
        if !motion.isEmpty { try c.encode(motion, forKey: .motion) }
    }

    /// Anzahl der zu speichernden Schritte: Länge bzw. letzter aktiver Schritt, auf ganze Seiten gerundet.
    var storedStepCount: Int {
        var last = length - 1
        for t in 0..<Self.trackCount {
            if let i = steps[t].lastIndex(where: \.active), i > last { last = i }
        }
        let pages = (last + Self.stepsPerPage) / Self.stepsPerPage
        return min(Self.maxSteps, max(1, pages) * Self.stepsPerPage)
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
        var seen = Set<String>()
        motion = motion.filter { lane in
            guard MotionLane.canRecord(lane.parameter) else { return false }
            return seen.insert("\(lane.parameter.rawValue)#\(lane.pad)").inserted
        }
        if motion.count > MotionLane.maxLanes { motion = Array(motion.prefix(MotionLane.maxLanes)) }
        for i in motion.indices { motion[i].normalize() }
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
        motion = []
    }

    public mutating func clearTrack(_ track: Int) {
        steps[track] = Array(repeating: SequencerStep(), count: Self.maxSteps)
    }

    public var isEmpty: Bool { !steps.contains { $0.contains { $0.active } } }

    public func activeStepCount(track: Int) -> Int {
        steps[track].prefix(length).filter(\.active).count
    }

    // MARK: Motion

    public func motionLaneIndex(parameter: ParameterID, pad: Int) -> Int? {
        let p = parameter.isPadParameter ? pad : -1
        return motion.firstIndex { $0.parameter == parameter && $0.pad == p }
    }

    public func hasMotion(parameter: ParameterID, pad: Int) -> Bool {
        motionLaneIndex(parameter: parameter, pad: pad) != nil
    }

    /// Zeichnet einen Wert auf. Liegt `fromStep` vor `step` (gleicher Durchlauf), werden
    /// die Schritte dazwischen linear aufgefüllt – eine Reglerbewegung füllt so alle Schritte.
    /// - Returns: `false`, wenn keine weitere Spur angelegt werden kann.
    @discardableResult
    public mutating func recordMotion(parameter: ParameterID, pad: Int, step: Int, value: Double,
                                      fromStep: Int? = nil, fromValue: Double? = nil) -> Bool {
        guard MotionLane.canRecord(parameter), (0..<Self.maxSteps).contains(step) else { return false }
        let index: Int
        if let i = motionLaneIndex(parameter: parameter, pad: pad) {
            index = i
        } else {
            guard motion.count < MotionLane.maxLanes else { return false }
            motion.append(MotionLane(parameter: parameter, pad: pad))
            index = motion.count - 1
        }
        let spec = parameter.spec
        let v = DSP.clamp(value, spec.minimum, spec.maximum)
        if let from = fromStep, let fv = fromValue, from < step, step - from <= Self.maxSteps / 2 {
            for s in (from + 1)..<step {
                let t = Double(s - from) / Double(step - from)
                motion[index].values[s] = fv + (v - fv) * t
            }
        }
        motion[index].values[step] = v
        return true
    }

    public mutating func removeMotion(parameter: ParameterID, pad: Int) {
        if let i = motionLaneIndex(parameter: parameter, pad: pad) { motion.remove(at: i) }
    }
}

/// Für den Audio-Thread vorberechnete Motion-Spur.
public struct MotionTrack: @unchecked Sendable {
    let padKeyPath: WritableKeyPath<PadSettings, Double>?
    let masterKeyPath: WritableKeyPath<MasterSettings, Double>?
    let pad: Int
    let parameter: ParameterID
    /// Wert je Schritt (Lücken mit dem vorigen Wert gefüllt, zyklisch)
    let hold: [Double]
    /// Wert je Schritt (Lücken linear zwischen den aufgezeichneten Werten interpoliert, zyklisch)
    let smooth: [Double]

    /// Wert an einer Position innerhalb des Patterns (Schritt + Bruchteil).
    @inline(__always)
    func value(step: Int, fraction: Double, mode: MotionMode) -> Double {
        if mode == .smooth {
            let a = smooth[step]
            let b = smooth[(step + 1) % smooth.count]
            return a + (b - a) * fraction
        }
        return hold[step]
    }
}

/// Unveränderliche, kompakte Kopie eines Patterns für den Audio-Thread.
public final class PatternSnapshot {
    public let length: Int
    /// Flaches Feld `track * maxSteps + step`
    public let steps: [SequencerStep]
    public let gates: [Double]
    let motion: [MotionTrack]
    /// Pads mit mindestens einer Motion-Spur (Bitmaske)
    let motionPadMask: UInt16
    let hasMasterMotion: Bool

    public init(_ pattern: SequencerPattern) {
        var p = pattern
        p.normalize()
        length = p.length
        steps = p.steps.flatMap { $0 }
        gates = p.gates
        var tracks: [MotionTrack] = []
        var mask: UInt16 = 0
        var master = false
        for lane in p.motion where lane.hasValues(length: p.length) {
            let (hold, smooth) = Self.fill(Array(lane.values.prefix(p.length)))
            tracks.append(MotionTrack(padKeyPath: lane.parameter.padKeyPath, masterKeyPath: lane.parameter.masterKeyPath,
                                      pad: lane.pad, parameter: lane.parameter, hold: hold, smooth: smooth))
            if lane.pad >= 0 { mask |= UInt16(1) << UInt16(lane.pad) } else { master = true }
        }
        motion = tracks
        motionPadMask = mask
        hasMasterMotion = master
    }

    public var hasMotion: Bool { !motion.isEmpty }

    /// Füllt Lücken einer Motion-Spur zyklisch auf (Stufen bzw. linear).
    static func fill(_ values: [Double?]) -> (hold: [Double], smooth: [Double]) {
        let n = values.count
        let defined = values.indices.filter { values[$0] != nil }
        guard let first = defined.first else { return ([], []) }
        var hold = [Double](repeating: 0, count: n)
        var smooth = [Double](repeating: 0, count: n)
        for s in 0..<n {
            // vorheriger definierter Schritt (zyklisch)
            let prev = defined.last { $0 <= s } ?? defined.last!
            let next = defined.first { $0 > s } ?? first
            let pv = values[prev]!, nv = values[next]!
            hold[s] = pv
            if prev == s || prev == next {
                smooth[s] = pv
            } else {
                let span = ((next - prev) % n + n) % n
                let pos = ((s - prev) % n + n) % n
                smooth[s] = pv + (nv - pv) * Double(pos) / Double(max(span, 1))
            }
        }
        return (hold, smooth)
    }

    @inline(__always)
    public func step(track: Int, step: Int) -> SequencerStep {
        steps[track * SequencerPattern.maxSteps + step]
    }
}

/// Reihenfolge der Patterns im Song-Modus (für den Audio-Thread).
public final class SongSnapshot {
    public let chain: [Int]
    public init(chain: [Int]) {
        let c = chain.filter { (0..<SequencerState.patternSlots).contains($0) }
        self.chain = c.isEmpty ? [0] : Array(c.prefix(64))
    }
}
