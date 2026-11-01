import Foundation

/// ADSR-Hüllkurve mit linearem Attack und exponentiellem Decay/Release.
/// Mindestzeiten verhindern Knackser beim Starten und Stoppen.
public struct ADSREnvelope {
    public enum Stage: Equatable { case idle, attack, decay, sustain, release }

    public static let minimumAttack: Double = 0.0005
    public static let minimumRelease: Double = 0.002

    public private(set) var stage: Stage = .idle
    public private(set) var level: Float = 0

    private var attackIncrement: Float = 1
    private var decayCoefficient: Float = 0
    private var releaseCoefficient: Float = 0
    private var sustainLevel: Float = 1
    private var sampleRate: Double = 44_100

    public init() {}

    public mutating func configure(attack: Double, decay: Double, sustain: Double, release: Double, sampleRate: Double) {
        self.sampleRate = sampleRate
        attackIncrement = Float(1.0 / (max(attack, Self.minimumAttack) * sampleRate))
        // Decay/Release erreichen nach der angegebenen Zeit -60 dB des Abstands.
        decayCoefficient = Float(exp(log(0.001) / (max(decay, 0.001) * sampleRate)))
        releaseCoefficient = Float(exp(log(0.001) / (max(release, Self.minimumRelease) * sampleRate)))
        sustainLevel = Float(DSP.clamp(sustain, 0, 1))
    }

    /// Startet die Hüllkurve vom aktuellen Pegel aus (kein Sprung bei Retrigger).
    public mutating func noteOn() { stage = .attack }

    public mutating func noteOff() {
        if stage != .idle { stage = .release }
    }

    /// Sehr schnelles Ausblenden (Voice-Stealing, Choke).
    public mutating func forceRelease(seconds: Double) {
        guard stage != .idle else { return }
        releaseCoefficient = Float(exp(log(0.001) / (max(seconds, 0.0005) * sampleRate)))
        stage = .release
    }

    public mutating func reset() {
        stage = .idle
        level = 0
    }

    public var isActive: Bool { stage != .idle }

    @inline(__always)
    public mutating func next() -> Float {
        switch stage {
        case .idle:
            return 0
        case .attack:
            level += attackIncrement
            if level >= 1 {
                level = 1
                stage = .decay
            }
        case .decay:
            level = sustainLevel + (level - sustainLevel) * decayCoefficient
            if abs(level - sustainLevel) < 0.0001 {
                level = sustainLevel
                stage = .sustain
            }
        case .sustain:
            level = sustainLevel
            if sustainLevel <= 0.0001 { stage = .idle; level = 0 }
        case .release:
            level *= releaseCoefficient
            if level < 0.0001 {
                level = 0
                stage = .idle
            }
        }
        return level
    }
}
