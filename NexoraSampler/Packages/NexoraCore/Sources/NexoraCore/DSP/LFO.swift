import Foundation

public enum LFOShape: String, Codable, CaseIterable, Sendable {
    case sine, triangle, square, sawUp, sawDown, sampleHold

    public var shortName: String {
        switch self {
        case .sine: return "SIN"
        case .triangle: return "TRI"
        case .square: return "SQR"
        case .sawUp: return "SAW"
        case .sawDown: return "RMP"
        case .sampleHold: return "S&H"
        }
    }
}

/// Niederfrequenz-Oszillator, Ausgabe -1 ... 1.
public struct LFO {
    public private(set) var phase: Double = 0
    private var holdValue: Float = 0
    private var random = FastRandom(seed: 0xC0FFEE)

    public init(phase: Double = 0) { self.phase = phase }

    public mutating func reset(phase: Double = 0) { self.phase = phase }

    @inline(__always)
    public func value(shape: LFOShape) -> Float {
        let p = Float(phase)
        switch shape {
        case .sine: return sinf(2 * Float.pi * p)
        case .triangle: return p < 0.5 ? (4 * p - 1) : (3 - 4 * p)
        case .square: return p < 0.5 ? 1 : -1
        case .sawUp: return 2 * p - 1
        case .sawDown: return 1 - 2 * p
        case .sampleHold: return holdValue
        }
    }

    /// Liefert den aktuellen Wert und rückt um `samples` Samples vor.
    @inline(__always)
    public mutating func next(shape: LFOShape, rate: Double, sampleRate: Double, samples: Int = 1) -> Float {
        let v = value(shape: shape)
        phase += rate * Double(samples) / sampleRate
        if phase >= 1 {
            phase -= floor(phase)
            holdValue = random.nextBipolar()
        }
        return v
    }
}
