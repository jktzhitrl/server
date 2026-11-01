import Foundation

/// Filtertyp für Pad- und Master-Filter.
public enum FilterMode: String, Codable, CaseIterable, Sendable {
    case off
    case lowPass
    case highPass
    case bandPass

    public var shortName: String {
        switch self {
        case .off: return "OFF"
        case .lowPass: return "LP"
        case .highPass: return "HP"
        case .bandPass: return "BP"
        }
    }
}

/// Zustandsvariablen-Filter in TPT-Struktur (Zavalishin/Simper).
/// Stabil auch bei schneller Modulation von Cutoff und Resonanz, daher für
/// LFO- und XY-Pad-Steuerung geeignet. Stereo, 12 dB/Oktave.
public struct StateVariableFilter {
    private var ic1L: Float = 0, ic2L: Float = 0
    private var ic1R: Float = 0, ic2R: Float = 0
    private var k: Float = 2
    private var a1: Float = 0, a2: Float = 0, a3: Float = 0
    public var mode: FilterMode = .lowPass

    public init() { setParameters(cutoff: 1000, resonance: 0, sampleRate: 44_100) }

    /// - Parameters:
    ///   - cutoff: Grenzfrequenz in Hz
    ///   - resonance: 0 ... 1 (1 = kurz vor Selbstoszillation)
    public mutating func setParameters(cutoff: Float, resonance: Float, sampleRate: Float) {
        let fc = DSP.clamp(cutoff, 10, sampleRate * 0.49)
        let g = tanf(Float.pi * fc / sampleRate)
        k = 2 - 1.96 * DSP.clamp(resonance, 0, 1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    public mutating func reset() {
        ic1L = 0; ic2L = 0; ic1R = 0; ic2R = 0
    }

    @inline(__always)
    private func output(_ x: Float, _ v1: Float, _ v2: Float) -> Float {
        switch mode {
        case .off: return x
        case .lowPass: return v2
        case .highPass: return x - k * v1 - v2
        case .bandPass: return k * v1
        }
    }

    @inline(__always)
    public mutating func process(_ left: Float, _ right: Float) -> (Float, Float) {
        if mode == .off { return (left, right) }
        let v3L = left - ic2L
        let v1L = a1 * ic1L + a2 * v3L
        let v2L = ic2L + a2 * ic1L + a3 * v3L
        ic1L = DSP.flushDenormal(2 * v1L - ic1L)
        ic2L = DSP.flushDenormal(2 * v2L - ic2L)

        let v3R = right - ic2R
        let v1R = a1 * ic1R + a2 * v3R
        let v2R = ic2R + a2 * ic1R + a3 * v3R
        ic1R = DSP.flushDenormal(2 * v1R - ic1R)
        ic2R = DSP.flushDenormal(2 * v2R - ic2R)

        return (output(left, v1L, v2L), output(right, v1R, v2R))
    }

    @inline(__always)
    public mutating func processMono(_ x: Float) -> Float {
        if mode == .off { return x }
        let v3 = x - ic2L
        let v1 = a1 * ic1L + a2 * v3
        let v2 = ic2L + a2 * ic1L + a3 * v3
        ic1L = DSP.flushDenormal(2 * v1 - ic1L)
        ic2L = DSP.flushDenormal(2 * v2 - ic2L)
        return output(x, v1, v2)
    }
}
