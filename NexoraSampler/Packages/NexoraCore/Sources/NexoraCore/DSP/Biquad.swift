import Foundation

/// RBJ-Biquad (Audio EQ Cookbook) in transponierter Direktform II, stereo.
public struct Biquad {
    public enum Kind { case lowShelf, peaking, highShelf, lowPass, highPass }

    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1L: Float = 0, z2L: Float = 0, z1R: Float = 0, z2R: Float = 0
    public private(set) var isIdentity = true

    public init() {}

    public mutating func configure(kind: Kind, frequency: Double, q: Double, gainDb: Double, sampleRate: Double) {
        let f = min(max(frequency, 10), sampleRate * 0.49)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosw = cos(w0), sinw = sin(w0)
        let A = pow(10, gainDb / 40)
        let alpha = sinw / (2 * max(q, 0.05))
        var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0
        switch kind {
        case .peaking:
            nb0 = 1 + alpha * A; nb1 = -2 * cosw; nb2 = 1 - alpha * A
            na0 = 1 + alpha / A; na1 = -2 * cosw; na2 = 1 - alpha / A
        case .lowShelf:
            let s = 2 * sqrt(A) * alpha
            nb0 = A * ((A + 1) - (A - 1) * cosw + s)
            nb1 = 2 * A * ((A - 1) - (A + 1) * cosw)
            nb2 = A * ((A + 1) - (A - 1) * cosw - s)
            na0 = (A + 1) + (A - 1) * cosw + s
            na1 = -2 * ((A - 1) + (A + 1) * cosw)
            na2 = (A + 1) + (A - 1) * cosw - s
        case .highShelf:
            let s = 2 * sqrt(A) * alpha
            nb0 = A * ((A + 1) + (A - 1) * cosw + s)
            nb1 = -2 * A * ((A - 1) + (A + 1) * cosw)
            nb2 = A * ((A + 1) + (A - 1) * cosw - s)
            na0 = (A + 1) - (A - 1) * cosw + s
            na1 = 2 * ((A - 1) - (A + 1) * cosw)
            na2 = (A + 1) - (A - 1) * cosw - s
        case .lowPass:
            nb0 = (1 - cosw) / 2; nb1 = 1 - cosw; nb2 = (1 - cosw) / 2
            na0 = 1 + alpha; na1 = -2 * cosw; na2 = 1 - alpha
        case .highPass:
            nb0 = (1 + cosw) / 2; nb1 = -(1 + cosw); nb2 = (1 + cosw) / 2
            na0 = 1 + alpha; na1 = -2 * cosw; na2 = 1 - alpha
        }
        b0 = Float(nb0 / na0); b1 = Float(nb1 / na0); b2 = Float(nb2 / na0)
        a1 = Float(na1 / na0); a2 = Float(na2 / na0)
        isIdentity = (kind == .peaking || kind == .lowShelf || kind == .highShelf) && abs(gainDb) < 0.01
    }

    public mutating func reset() { z1L = 0; z2L = 0; z1R = 0; z2R = 0 }

    @inline(__always)
    public mutating func process(_ left: Float, _ right: Float) -> (Float, Float) {
        let yL = b0 * left + z1L
        z1L = DSP.flushDenormal(b1 * left - a1 * yL + z2L)
        z2L = DSP.flushDenormal(b2 * left - a2 * yL)
        let yR = b0 * right + z1R
        z1R = DSP.flushDenormal(b1 * right - a1 * yR + z2R)
        z2R = DSP.flushDenormal(b2 * right - a2 * yR)
        return (yL, yR)
    }

    @inline(__always)
    public mutating func processMono(_ x: Float) -> Float {
        let y = b0 * x + z1L
        z1L = DSP.flushDenormal(b1 * x - a1 * y + z2L)
        z2L = DSP.flushDenormal(b2 * x - a2 * y)
        return y
    }
}
