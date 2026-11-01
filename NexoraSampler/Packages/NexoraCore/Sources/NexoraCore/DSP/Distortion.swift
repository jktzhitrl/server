import Foundation

/// Weiche Sättigung (tanh-Kennlinie) mit Pegelkompensation.
public struct Distortion {
    public init() {}

    /// - Parameters:
    ///   - drive: 0 ... 1 (0 = neutral)
    @inline(__always)
    public static func process(_ x: Float, drive: Float) -> Float {
        guard drive > 0.0001 else { return x }
        let g = 1 + drive * drive * 40
        let norm = 1 / DSP.fastTanh(min(g, 3))
        return DSP.fastTanh(x * g) * norm * (1 - 0.35 * drive)
    }
}

/// Bitcrusher: Reduktion der Bittiefe und der effektiven Abtastrate (Sample & Hold).
public struct Bitcrusher {
    private var counter: Float = 0
    private var holdL: Float = 0
    private var holdR: Float = 0

    public init() {}

    public mutating func reset() { counter = 0; holdL = 0; holdR = 0 }

    /// - Parameters:
    ///   - bits: 1 ... 16 (16 = keine Reduktion)
    ///   - downsample: 1 ... 64 (1 = keine Reduktion)
    @inline(__always)
    public mutating func process(_ left: Float, _ right: Float, bits: Float, downsample: Float) -> (Float, Float) {
        if bits >= 15.99 && downsample <= 1.001 { return (left, right) }
        if counter <= 0 {
            counter += max(downsample, 1)
            holdL = left
            holdR = right
        }
        counter -= 1
        if bits >= 15.99 { return (holdL, holdR) }
        let levels = powf(2, max(bits, 1) - 1)
        return ((holdL * levels).rounded() / levels, (holdR * levels).rounded() / levels)
    }
}
