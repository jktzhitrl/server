import Foundation

/// Kennung eines steuerbaren Parameters. Wird von Drehreglern, XY-Pad und MIDI-CC-Mapping
/// gemeinsam verwendet. `pad*`-Parameter beziehen sich auf das ausgewählte Pad.
public enum ParameterID: String, Codable, CaseIterable, Sendable {
    // Pad
    case padVolume, padPan, padPitch, padFineTune, padSpeed, padStart, padEnd
    case padAttack, padDecay, padSustain, padRelease
    case padCutoff, padResonance, padFilterEnv
    case padLFORate, padLFODepth
    case padDrive, padCrushBits, padCrushRate
    case padReverbSend, padDelaySend, padVelocitySensitivity
    // Master
    case masterVolume
    case masterFilterCutoff, masterFilterResonance
    case masterDrive, masterCrushBits, masterCrushRate
    case delayTime, delayFeedback, delayMix, delayDamping
    case reverbSize, reverbDamping, reverbMix, reverbWidth
    case eqLow, eqMid, eqHigh, eqMidFrequency
    case compThreshold, compRatio, compAttack, compRelease, compMakeup
    case modRate, modDepth
    // Projekt
    case tempo, swing

    public var isPadParameter: Bool { rawValue.hasPrefix("pad") }

    public var spec: ParameterSpec { ParameterSpec.spec(for: self) }
}

public enum ParameterTaper: Sendable {
    case linear
    /// Logarithmisch (für Frequenzen und Zeiten), `min` muss > 0 sein
    case exponential
    /// Quadratisch – annähernd logarithmischer Lautstärkeverlauf
    case quadratic
}

public enum ParameterUnit: Sendable {
    case percent, hertz, decibel, seconds, semitones, cents, ratio, bits, bpm, factor, pan, gain, swing, divisor
}

/// Wertebereich, Kennlinie und Darstellung eines Parameters.
public struct ParameterSpec: Sendable {
    public let id: ParameterID
    public let name: String
    /// Kurzbezeichnung für Regler und LCD (max. ~8 Zeichen)
    public let shortName: String
    public let minimum: Double
    public let maximum: Double
    public let defaultValue: Double
    public let taper: ParameterTaper
    public let unit: ParameterUnit
    public let isInteger: Bool

    init(_ id: ParameterID, _ name: String, _ short: String, _ minimum: Double, _ maximum: Double,
         _ defaultValue: Double, _ taper: ParameterTaper = .linear, _ unit: ParameterUnit, integer: Bool = false) {
        self.id = id
        self.name = name
        self.shortName = short
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
        self.taper = taper
        self.unit = unit
        self.isInteger = integer
    }

    /// Wandelt einen normierten Wert (0 ... 1) in den Parameterwert um.
    public func value(fromNormalized n: Double) -> Double {
        let t = DSP.clamp(n, 0, 1)
        var v: Double
        switch taper {
        case .linear: v = minimum + t * (maximum - minimum)
        case .exponential: v = minimum * pow(maximum / minimum, t)
        case .quadratic: v = minimum + t * t * (maximum - minimum)
        }
        if isInteger { v = v.rounded() }
        return DSP.clamp(v, minimum, maximum)
    }

    /// Wandelt einen Parameterwert in den normierten Bereich (0 ... 1) um.
    public func normalized(fromValue value: Double) -> Double {
        let v = DSP.clamp(value, minimum, maximum)
        guard maximum > minimum else { return 0 }
        switch taper {
        case .linear: return (v - minimum) / (maximum - minimum)
        case .exponential: return log(v / minimum) / log(maximum / minimum)
        case .quadratic: return sqrt((v - minimum) / (maximum - minimum))
        }
    }

    public var defaultNormalized: Double { normalized(fromValue: defaultValue) }

    /// Formatierte Darstellung für LCD und Regler.
    public func format(_ value: Double) -> String {
        switch unit {
        case .percent: return "\(Int((value * 100).rounded()))%"
        case .hertz:
            return value >= 1000 ? String(format: "%.2fk", value / 1000) : String(format: "%.0fHz", value)
        case .decibel: return String(format: "%+.1fdB", value)
        case .seconds:
            return value < 1 ? String(format: "%.0fms", value * 1000) : String(format: "%.2fs", value)
        case .semitones: return String(format: "%+.0fst", value)
        case .cents: return String(format: "%+.0fct", value)
        case .ratio: return String(format: "%.1f:1", value)
        case .bits: return String(format: "%.0fbit", value)
        case .bpm: return String(format: "%.1f", value)
        case .factor: return String(format: "%.2fx", value)
        case .pan:
            if abs(value) < 0.01 { return "C" }
            return value < 0 ? "L\(Int((-value * 100).rounded()))" : "R\(Int((value * 100).rounded()))"
        case .gain:
            return value <= 0.0001 ? "-inf" : String(format: "%.1fdB", 20 * log10(value))
        case .swing: return String(format: "%.0f%%", value)
        case .divisor: return value <= 1.01 ? "OFF" : String(format: "1/%.0f", value)
        }
    }

    static func spec(for id: ParameterID) -> ParameterSpec {
        switch id {
        case .padVolume: return .init(id, "Pad Volume", "VOLUME", 0, 1.25, 0.8, .quadratic, .gain)
        case .padPan: return .init(id, "Pad Pan", "PAN", -1, 1, 0, .linear, .pan)
        case .padPitch: return .init(id, "Pad Pitch", "PITCH", -24, 24, 0, .linear, .semitones, integer: true)
        case .padFineTune: return .init(id, "Fine Tune", "FINE", -100, 100, 0, .linear, .cents)
        case .padSpeed: return .init(id, "Playback Speed", "SPEED", 0.25, 4, 1, .exponential, .factor)
        case .padStart: return .init(id, "Sample Start", "START", 0, 1, 0, .linear, .percent)
        case .padEnd: return .init(id, "Sample End", "END", 0, 1, 1, .linear, .percent)
        case .padAttack: return .init(id, "Attack", "ATTACK", 0.0005, 4, 0.001, .exponential, .seconds)
        case .padDecay: return .init(id, "Decay", "DECAY", 0.005, 8, 0.4, .exponential, .seconds)
        case .padSustain: return .init(id, "Sustain", "SUSTAIN", 0, 1, 1, .linear, .percent)
        case .padRelease: return .init(id, "Release", "RELEASE", 0.002, 8, 0.08, .exponential, .seconds)
        case .padCutoff: return .init(id, "Pad Filter Cutoff", "CUTOFF", 20, 20_000, 18_000, .exponential, .hertz)
        case .padResonance: return .init(id, "Pad Resonance", "RESO", 0, 1, 0.1, .linear, .percent)
        case .padFilterEnv: return .init(id, "Filter EG Intensity", "EG INT", -1, 1, 0, .linear, .percent)
        case .padLFORate: return .init(id, "Pad LFO Rate", "LFO RATE", 0.05, 30, 4, .exponential, .hertz)
        case .padLFODepth: return .init(id, "Pad LFO Depth", "LFO AMT", 0, 1, 0, .linear, .percent)
        case .padDrive: return .init(id, "Pad Drive", "DRIVE", 0, 1, 0, .linear, .percent)
        case .padCrushBits: return .init(id, "Pad Bit Depth", "BITS", 1, 16, 16, .linear, .bits)
        case .padCrushRate: return .init(id, "Pad Downsample", "RATE", 1, 32, 1, .exponential, .divisor)
        case .padReverbSend: return .init(id, "Reverb Send", "REV SND", 0, 1, 1, .linear, .percent)
        case .padDelaySend: return .init(id, "Delay Send", "DLY SND", 0, 1, 1, .linear, .percent)
        case .padVelocitySensitivity: return .init(id, "Velocity Sensitivity", "VELO", 0, 1, 0.7, .linear, .percent)
        case .masterVolume: return .init(id, "Master Volume", "MASTER", 0, 1.25, 0.8, .quadratic, .gain)
        case .masterFilterCutoff: return .init(id, "Filter Cutoff", "FILTER", 20, 20_000, 20_000, .exponential, .hertz)
        case .masterFilterResonance: return .init(id, "Filter Resonance", "RESO", 0, 1, 0.15, .linear, .percent)
        case .masterDrive: return .init(id, "Distortion", "DRIVE", 0, 1, 0, .linear, .percent)
        case .masterCrushBits: return .init(id, "Bitcrusher Depth", "BITS", 1, 16, 16, .linear, .bits)
        case .masterCrushRate: return .init(id, "Bitcrusher Rate", "CRUSH", 1, 32, 1, .exponential, .divisor)
        case .delayTime: return .init(id, "Delay Time", "TIME", 0.01, 2, 0.375, .exponential, .seconds)
        case .delayFeedback: return .init(id, "Delay Feedback", "FEEDBK", 0, 0.95, 0.35, .linear, .percent)
        case .delayMix: return .init(id, "Delay Mix", "DELAY", 0, 1, 0, .linear, .percent)
        case .delayDamping: return .init(id, "Delay Tone", "D.TONE", 0, 0.95, 0.3, .linear, .percent)
        case .reverbSize: return .init(id, "Reverb Size", "SIZE", 0, 1, 0.75, .linear, .percent)
        case .reverbDamping: return .init(id, "Reverb Damping", "DAMP", 0, 1, 0.4, .linear, .percent)
        case .reverbMix: return .init(id, "Reverb Mix", "REVERB", 0, 1, 0, .linear, .percent)
        case .reverbWidth: return .init(id, "Reverb Width", "WIDTH", 0, 1, 1, .linear, .percent)
        case .eqLow: return .init(id, "EQ Low", "LOW", -15, 15, 0, .linear, .decibel)
        case .eqMid: return .init(id, "EQ Mid", "MID", -15, 15, 0, .linear, .decibel)
        case .eqHigh: return .init(id, "EQ High", "HIGH", -15, 15, 0, .linear, .decibel)
        case .eqMidFrequency: return .init(id, "EQ Mid Frequency", "MID FRQ", 200, 8_000, 1_000, .exponential, .hertz)
        case .compThreshold: return .init(id, "Compressor Threshold", "COMP", -40, 0, 0, .linear, .decibel)
        case .compRatio: return .init(id, "Compressor Ratio", "RATIO", 1, 20, 4, .exponential, .ratio)
        case .compAttack: return .init(id, "Compressor Attack", "C.ATK", 0.0005, 0.2, 0.01, .exponential, .seconds)
        case .compRelease: return .init(id, "Compressor Release", "C.REL", 0.01, 2, 0.15, .exponential, .seconds)
        case .compMakeup: return .init(id, "Compressor Makeup", "MAKEUP", 0, 24, 0, .linear, .decibel)
        case .modRate: return .init(id, "LFO Rate", "LFO", 0.05, 20, 2, .exponential, .hertz)
        case .modDepth: return .init(id, "Modulation Depth", "MOD", 0, 1, 0, .linear, .percent)
        case .tempo: return .init(id, "Tempo", "TEMPO", 40, 300, 120, .linear, .bpm)
        case .swing: return .init(id, "Swing", "SWING", 50, 75, 50, .linear, .swing)
        }
    }
}

extension ParameterID {
    var padKeyPath: WritableKeyPath<PadSettings, Double>? {
        switch self {
        case .padVolume: return \.volume
        case .padPan: return \.pan
        case .padPitch: return \.pitch
        case .padFineTune: return \.fineTune
        case .padSpeed: return \.speed
        case .padStart: return \.start
        case .padEnd: return \.end
        case .padAttack: return \.attack
        case .padDecay: return \.decay
        case .padSustain: return \.sustain
        case .padRelease: return \.release
        case .padCutoff: return \.cutoff
        case .padResonance: return \.resonance
        case .padFilterEnv: return \.filterEnvAmount
        case .padLFORate: return \.lfoRate
        case .padLFODepth: return \.lfoDepth
        case .padDrive: return \.drive
        case .padCrushBits: return \.crushBits
        case .padCrushRate: return \.crushDownsample
        case .padReverbSend: return \.reverbSend
        case .padDelaySend: return \.delaySend
        case .padVelocitySensitivity: return \.velocitySensitivity
        default: return nil
        }
    }

    var masterKeyPath: WritableKeyPath<MasterSettings, Double>? {
        switch self {
        case .masterVolume: return \.volume
        case .masterFilterCutoff: return \.filterCutoff
        case .masterFilterResonance: return \.filterResonance
        case .masterDrive: return \.drive
        case .masterCrushBits: return \.crushBits
        case .masterCrushRate: return \.crushDownsample
        case .delayTime: return \.delayTime
        case .delayFeedback: return \.delayFeedback
        case .delayMix: return \.delayMix
        case .delayDamping: return \.delayDamping
        case .reverbSize: return \.reverbSize
        case .reverbDamping: return \.reverbDamping
        case .reverbMix: return \.reverbMix
        case .reverbWidth: return \.reverbWidth
        case .eqLow: return \.eqLow
        case .eqMid: return \.eqMid
        case .eqHigh: return \.eqHigh
        case .eqMidFrequency: return \.eqMidFrequency
        case .compThreshold: return \.compThreshold
        case .compRatio: return \.compRatio
        case .compAttack: return \.compAttack
        case .compRelease: return \.compRelease
        case .compMakeup: return \.compMakeup
        case .modRate: return \.modRate
        case .modDepth: return \.modDepth
        default: return nil
        }
    }
}

/// Bereich, in dem eine Parameteränderung wirkt – damit die App gezielt nur die
/// betroffenen Einstellungen an die Audio-Engine schickt.
public enum ParameterScope: Equatable, Sendable {
    case pad(Int)
    case master
    case tempo
}

extension ProjectDocument {
    /// Aktueller Wert eines Parameters (Pad-Parameter beziehen sich auf `pad`).
    public func value(of id: ParameterID, pad: Int) -> Double {
        if let kp = id.padKeyPath { return pads[DSP.clamp(pad, 0, 15)].settings[keyPath: kp] }
        if let kp = id.masterKeyPath { return master[keyPath: kp] }
        switch id {
        case .tempo: return bpm
        case .swing: return swing
        default: return id.spec.defaultValue
        }
    }

    /// Setzt einen Parameter (auf den gültigen Bereich begrenzt) und liefert den Wirkungsbereich.
    @discardableResult
    public mutating func setValue(_ value: Double, for id: ParameterID, pad: Int) -> ParameterScope {
        let spec = id.spec
        var v = DSP.clamp(value, spec.minimum, spec.maximum)
        if spec.isInteger { v = v.rounded() }
        let p = DSP.clamp(pad, 0, 15)
        if let kp = id.padKeyPath {
            pads[p].settings[keyPath: kp] = v
            // Start darf das Ende nicht überholen (und umgekehrt).
            if id == .padStart, pads[p].settings.end < v + 0.001 { pads[p].settings.end = min(1, v + 0.001) }
            if id == .padEnd, pads[p].settings.start > v - 0.001 { pads[p].settings.start = max(0, v - 0.001) }
            return .pad(p)
        }
        if let kp = id.masterKeyPath {
            master[keyPath: kp] = v
            if id == .delayTime { master.delaySync = .off }
            return .master
        }
        switch id {
        case .tempo: bpm = v
        case .swing: swing = v
        default: break
        }
        return .tempo
    }

    public func normalizedValue(of id: ParameterID, pad: Int) -> Double {
        id.spec.normalized(fromValue: value(of: id, pad: pad))
    }

    @discardableResult
    public mutating func setNormalizedValue(_ n: Double, for id: ParameterID, pad: Int) -> ParameterScope {
        setValue(id.spec.value(fromNormalized: n), for: id, pad: pad)
    }
}
