import Foundation

/// Notenwert für tempo-synchronisierte Effekte.
public enum TempoDivision: String, Codable, CaseIterable, Sendable {
    case off, whole, half, quarter, dottedEighth, eighth, tripletEighth, sixteenth, tripletSixteenth, thirtySecond

    /// Dauer in Vierteln (Beats); `nil` bei `.off`.
    public var beats: Double? {
        switch self {
        case .off: return nil
        case .whole: return 4
        case .half: return 2
        case .quarter: return 1
        case .dottedEighth: return 0.75
        case .eighth: return 0.5
        case .tripletEighth: return 1.0 / 3.0
        case .sixteenth: return 0.25
        case .tripletSixteenth: return 1.0 / 6.0
        case .thirtySecond: return 0.125
        }
    }

    public var shortName: String {
        switch self {
        case .off: return "FREE"
        case .whole: return "1/1"
        case .half: return "1/2"
        case .quarter: return "1/4"
        case .dottedEighth: return "1/8."
        case .eighth: return "1/8"
        case .tripletEighth: return "1/8T"
        case .sixteenth: return "1/16"
        case .tripletSixteenth: return "1/16T"
        case .thirtySecond: return "1/32"
        }
    }
}

/// Ziel des Master-Modulations-LFOs.
public enum MasterModTarget: String, Codable, CaseIterable, Sendable {
    case filter, tremolo, vibrato, pan

    public var shortName: String {
        switch self {
        case .filter: return "FILTER"
        case .tremolo: return "TREMOLO"
        case .vibrato: return "VIBRATO"
        case .pan: return "AUTOPAN"
        }
    }
}

/// Einstellungen der Master-Effektkette.
/// Signalfluss: Pads → (Dry + Delay-Return + Reverb-Return) → Filter → Drive → Bitcrusher
/// → Modulation → EQ → Kompressor → Master-Volume → Ausgang.
public struct MasterSettings: Codable, Equatable, Sendable {
    public var volume: Double = 0.8

    public var filterMode: FilterMode = .lowPass
    public var filterCutoff: Double = 20_000
    public var filterResonance: Double = 0.15

    public var drive: Double = 0
    public var crushBits: Double = 16
    public var crushDownsample: Double = 1

    public var delayTime: Double = 0.375
    public var delaySync: TempoDivision = .dottedEighth
    public var delayFeedback: Double = 0.35
    public var delayMix: Double = 0
    public var delayPingPong: Bool = true
    public var delayDamping: Double = 0.3

    public var reverbSize: Double = 0.75
    public var reverbDamping: Double = 0.4
    public var reverbMix: Double = 0
    public var reverbWidth: Double = 1

    public var eqLow: Double = 0
    public var eqMid: Double = 0
    public var eqHigh: Double = 0
    public var eqMidFrequency: Double = 1_000

    public var compThreshold: Double = 0
    public var compRatio: Double = 4
    public var compAttack: Double = 0.01
    public var compRelease: Double = 0.15
    public var compMakeup: Double = 0

    public var modRate: Double = 2
    public var modDepth: Double = 0
    public var modShape: LFOShape = .sine
    public var modTarget: MasterModTarget = .filter

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MasterSettings()
        volume = c.value(.volume, default: d.volume)
        filterMode = c.value(.filterMode, default: d.filterMode)
        filterCutoff = c.value(.filterCutoff, default: d.filterCutoff)
        filterResonance = c.value(.filterResonance, default: d.filterResonance)
        drive = c.value(.drive, default: d.drive)
        crushBits = c.value(.crushBits, default: d.crushBits)
        crushDownsample = c.value(.crushDownsample, default: d.crushDownsample)
        delayTime = c.value(.delayTime, default: d.delayTime)
        delaySync = c.value(.delaySync, default: d.delaySync)
        delayFeedback = c.value(.delayFeedback, default: d.delayFeedback)
        delayMix = c.value(.delayMix, default: d.delayMix)
        delayPingPong = c.value(.delayPingPong, default: d.delayPingPong)
        delayDamping = c.value(.delayDamping, default: d.delayDamping)
        reverbSize = c.value(.reverbSize, default: d.reverbSize)
        reverbDamping = c.value(.reverbDamping, default: d.reverbDamping)
        reverbMix = c.value(.reverbMix, default: d.reverbMix)
        reverbWidth = c.value(.reverbWidth, default: d.reverbWidth)
        eqLow = c.value(.eqLow, default: d.eqLow)
        eqMid = c.value(.eqMid, default: d.eqMid)
        eqHigh = c.value(.eqHigh, default: d.eqHigh)
        eqMidFrequency = c.value(.eqMidFrequency, default: d.eqMidFrequency)
        compThreshold = c.value(.compThreshold, default: d.compThreshold)
        compRatio = c.value(.compRatio, default: d.compRatio)
        compAttack = c.value(.compAttack, default: d.compAttack)
        compRelease = c.value(.compRelease, default: d.compRelease)
        compMakeup = c.value(.compMakeup, default: d.compMakeup)
        modRate = c.value(.modRate, default: d.modRate)
        modDepth = c.value(.modDepth, default: d.modDepth)
        modShape = c.value(.modShape, default: d.modShape)
        modTarget = c.value(.modTarget, default: d.modTarget)
    }

    /// Effektive Delay-Zeit in Sekunden unter Berücksichtigung der Tempo-Synchronisation.
    public func effectiveDelaySeconds(bpm: Double) -> Double {
        if let beats = delaySync.beats, bpm > 0 { return beats * 60 / bpm }
        return delayTime
    }
}

/// Strategie, wenn die maximale Stimmenzahl erreicht ist.
public enum VoiceStealMode: String, Codable, CaseIterable, Sendable {
    /// Älteste Stimme wird ersetzt
    case oldest
    /// Leiseste Stimme wird ersetzt
    case quietest
    /// Bevorzugt eine Stimme desselben Pads, sonst die älteste
    case samePad
    /// Keine Übernahme – neue Noten werden verworfen
    case none

    public var shortName: String {
        switch self {
        case .oldest: return "OLDEST"
        case .quietest: return "QUIETEST"
        case .samePad: return "SAME PAD"
        case .none: return "NO STEAL"
        }
    }
}

public struct EngineSettings: Codable, Equatable, Sendable {
    public static let maximumPolyphony = 64

    public var polyphony: Int = 32
    public var stealMode: VoiceStealMode = .oldest

    public init(polyphony: Int = 32, stealMode: VoiceStealMode = .oldest) {
        self.polyphony = polyphony
        self.stealMode = stealMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        polyphony = DSP.clamp(c.value(.polyphony, default: 32), 1, Self.maximumPolyphony)
        stealMode = c.value(.stealMode, default: .oldest)
    }
}
