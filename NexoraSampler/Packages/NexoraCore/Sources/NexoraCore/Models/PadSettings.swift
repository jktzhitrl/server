import Foundation

/// Wiedergabemodus eines Pads.
public enum PlayMode: String, Codable, CaseIterable, Sendable {
    /// Spielt den Sample-Bereich vollständig ab, Note-Off wird ignoriert.
    case oneShot
    /// Spielt, solange das Pad gehalten wird (Note-Off startet die Release-Phase).
    case gate
    /// Wiederholt den Sample-Bereich, solange das Pad gehalten wird.
    case loop

    public var shortName: String {
        switch self {
        case .oneShot: return "ONE"
        case .gate: return "GATE"
        case .loop: return "LOOP"
        }
    }
}

/// Verfahren für Tonhöhe/Geschwindigkeit.
public enum PitchMode: String, Codable, CaseIterable, Sendable {
    /// Klassisches Sampler-Verhalten: Tonhöhe und Geschwindigkeit gekoppelt (Resampling).
    case varispeed
    /// Granulares Time-Stretching: Tonhöhe und Geschwindigkeit unabhängig.
    case timeStretch

    public var shortName: String { self == .varispeed ? "VARI" : "STRETCH" }
}

/// Ziel des Pad-LFOs.
public enum PadLFOTarget: String, Codable, CaseIterable, Sendable {
    case off
    /// Vibrato (Tonhöhe)
    case pitch
    /// Tremolo (Lautstärke)
    case volume
    /// Filter-Cutoff
    case cutoff
    /// Auto-Pan
    case pan

    public var shortName: String {
        switch self {
        case .off: return "OFF"
        case .pitch: return "VIB"
        case .volume: return "TREM"
        case .cutoff: return "FILT"
        case .pan: return "PAN"
        }
    }
}

/// Alle klangrelevanten Einstellungen eines Pads. Reiner Werttyp ohne Heap-Speicher,
/// daher gefahrlos in den Audio-Thread kopierbar.
public struct PadSettings: Codable, Equatable, Sendable {
    /// Lineare Verstärkung 0 ... 1.25
    public var volume: Double = 0.8
    /// -1 (links) ... 1 (rechts)
    public var pan: Double = 0
    /// Halbtöne -24 ... 24
    public var pitch: Double = 0
    /// Cent -100 ... 100
    public var fineTune: Double = 0
    /// Wiedergabegeschwindigkeit 0.25 ... 4
    public var speed: Double = 1
    public var pitchMode: PitchMode = .varispeed
    /// Startposition 0 ... 1 (relativ zur Sample-Länge)
    public var start: Double = 0
    /// Endposition 0 ... 1 (relativ zur Sample-Länge)
    public var end: Double = 1
    public var reverse: Bool = false
    public var playMode: PlayMode = .oneShot

    /// Hüllkurve, Zeiten in Sekunden
    public var attack: Double = 0.001
    public var decay: Double = 0.4
    public var sustain: Double = 1
    public var release: Double = 0.08

    public var filterMode: FilterMode = .off
    /// Hz
    public var cutoff: Double = 18_000
    /// 0 ... 1
    public var resonance: Double = 0.1

    /// Hz
    public var lfoRate: Double = 4
    /// 0 ... 1
    public var lfoDepth: Double = 0
    public var lfoShape: LFOShape = .sine
    public var lfoTarget: PadLFOTarget = .off

    /// 0 ... 1
    public var drive: Double = 0
    /// 1 ... 16
    public var crushBits: Double = 16
    /// 1 ... 32
    public var crushDownsample: Double = 1

    /// Send-Pegel zu Hall und Delay (0 ... 1)
    public var reverbSend: Double = 1
    public var delaySend: Double = 1

    /// 0 = Anschlagstärke ignorieren, 1 = volle Dynamik
    public var velocitySensitivity: Double = 0.7
    /// 0 = keine Gruppe; Pads derselben Gruppe schneiden sich gegenseitig ab (z. B. Hi-Hats)
    public var chokeGroup: Int = 0
    /// Monophon: ein neuer Anschlag beendet die vorherige Stimme dieses Pads
    public var mono: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PadSettings()
        volume = c.value(.volume, default: d.volume)
        pan = c.value(.pan, default: d.pan)
        pitch = c.value(.pitch, default: d.pitch)
        fineTune = c.value(.fineTune, default: d.fineTune)
        speed = c.value(.speed, default: d.speed)
        pitchMode = c.value(.pitchMode, default: d.pitchMode)
        start = c.value(.start, default: d.start)
        end = c.value(.end, default: d.end)
        reverse = c.value(.reverse, default: d.reverse)
        playMode = c.value(.playMode, default: d.playMode)
        attack = c.value(.attack, default: d.attack)
        decay = c.value(.decay, default: d.decay)
        sustain = c.value(.sustain, default: d.sustain)
        release = c.value(.release, default: d.release)
        filterMode = c.value(.filterMode, default: d.filterMode)
        cutoff = c.value(.cutoff, default: d.cutoff)
        resonance = c.value(.resonance, default: d.resonance)
        lfoRate = c.value(.lfoRate, default: d.lfoRate)
        lfoDepth = c.value(.lfoDepth, default: d.lfoDepth)
        lfoShape = c.value(.lfoShape, default: d.lfoShape)
        lfoTarget = c.value(.lfoTarget, default: d.lfoTarget)
        drive = c.value(.drive, default: d.drive)
        crushBits = c.value(.crushBits, default: d.crushBits)
        crushDownsample = c.value(.crushDownsample, default: d.crushDownsample)
        reverbSend = c.value(.reverbSend, default: d.reverbSend)
        delaySend = c.value(.delaySend, default: d.delaySend)
        velocitySensitivity = c.value(.velocitySensitivity, default: d.velocitySensitivity)
        chokeGroup = c.value(.chokeGroup, default: d.chokeGroup)
        mono = c.value(.mono, default: d.mono)
    }
}
