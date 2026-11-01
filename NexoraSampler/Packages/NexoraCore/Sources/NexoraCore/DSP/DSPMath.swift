import Foundation

/// Grundlegende DSP-Hilfsfunktionen. Alle Funktionen sind allokationsfrei und
/// dürfen im Audio-Thread verwendet werden.
public enum DSP {
    @inline(__always)
    public static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }

    @inline(__always)
    public static func dbToGain(_ db: Float) -> Float { powf(10, db / 20) }

    @inline(__always)
    public static func gainToDb(_ gain: Float) -> Float {
        gain <= 1e-9 ? -180 : 20 * log10f(gain)
    }

    @inline(__always)
    public static func semitonesToRatio(_ semitones: Double) -> Double { pow(2, semitones / 12) }

    /// Koeffizient eines Einpol-Glättungsfilters: y += (1 - c) * (x - y).
    @inline(__always)
    public static func onePoleCoefficient(timeSeconds: Double, sampleRate: Double) -> Float {
        guard timeSeconds > 0, sampleRate > 0 else { return 0 }
        return Float(exp(-1.0 / (timeSeconds * sampleRate)))
    }

    /// Balance-Panning mit Einheitsverstärkung in der Mitte (geeignet für Stereo-Samples).
    @inline(__always)
    public static func balanceGains(_ pan: Float) -> (left: Float, right: Float) {
        let p = clamp(pan, -1, 1)
        return (min(1, 1 - p), min(1, 1 + p))
    }

    /// Rationale tanh-Näherung (Padé), für |x| > 3 gesättigt.
    @inline(__always)
    public static func fastTanh(_ x: Float) -> Float {
        if x > 3 { return 1 }
        if x < -3 { return -1 }
        let x2 = x * x
        return x * (27 + x2) / (27 + 9 * x2)
    }

    /// Kubische Hermite-Interpolation (4 Stützstellen).
    @inline(__always)
    public static func hermite(_ xm1: Float, _ x0: Float, _ x1: Float, _ x2: Float, _ t: Float) -> Float {
        let c0 = x0
        let c1 = 0.5 * (x1 - xm1)
        let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
        let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
        return ((c3 * t + c2) * t + c1) * t + c0
    }

    @inline(__always)
    public static func flushDenormal(_ x: Float) -> Float { abs(x) < 1e-20 ? 0 : x }
}

/// Einpol-geglätteter Parameter zur Vermeidung von "Zipper"-Geräuschen.
public struct SmoothedValue {
    public private(set) var current: Float
    public var target: Float
    private var coefficient: Float

    public init(value: Float, timeSeconds: Double = 0.01, sampleRate: Double = 44_100) {
        current = value
        target = value
        coefficient = DSP.onePoleCoefficient(timeSeconds: timeSeconds, sampleRate: sampleRate)
    }

    public mutating func configure(timeSeconds: Double, sampleRate: Double) {
        coefficient = DSP.onePoleCoefficient(timeSeconds: timeSeconds, sampleRate: sampleRate)
    }

    public mutating func reset(to value: Float) {
        current = value
        target = value
    }

    @inline(__always)
    public mutating func next() -> Float {
        current = target + coefficient * (current - target)
        if abs(current - target) < 1e-6 { current = target }
        return current
    }

    public var isSettled: Bool { current == target }
}

/// Einfacher, deterministischer Pseudozufallsgenerator (xorshift32) für den Audio-Thread.
public struct FastRandom {
    private var state: UInt32
    public init(seed: UInt32 = 0x1234_5678) { state = seed == 0 ? 0x1234_5678 : seed }

    @inline(__always)
    public mutating func nextUInt32() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// Gleichverteilt in -1 ... 1.
    @inline(__always)
    public mutating func nextBipolar() -> Float {
        Float(nextUInt32()) / Float(UInt32.max) * 2 - 1
    }
}
