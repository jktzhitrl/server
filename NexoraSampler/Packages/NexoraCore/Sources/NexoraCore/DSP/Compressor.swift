import Foundation

/// Stereo-gekoppelter Feed-Forward-Kompressor mit Soft-Knee.
public struct Compressor {
    public var thresholdDb: Float = 0
    public var ratio: Float = 4
    public var attackSeconds: Double = 0.01
    public var releaseSeconds: Double = 0.15
    public var makeupDb: Float = 0
    public var kneeDb: Float = 6

    private var envelopeDb: Float = -120
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var sampleRate: Double = 44_100
    public private(set) var currentGainReductionDb: Float = 0

    public init(sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        updateTimes()
    }

    public mutating func updateTimes() {
        attackCoeff = DSP.onePoleCoefficient(timeSeconds: max(attackSeconds, 0.0001), sampleRate: sampleRate)
        releaseCoeff = DSP.onePoleCoefficient(timeSeconds: max(releaseSeconds, 0.001), sampleRate: sampleRate)
    }

    public mutating func reset() { envelopeDb = -120; currentGainReductionDb = 0 }

    /// Statische Kennlinie: Pegelreduktion in dB (≤ 0) für einen Eingangspegel.
    @inline(__always)
    public func gainReduction(forInputDb x: Float) -> Float {
        let r = max(ratio, 1)
        let over = x - thresholdDb
        if 2 * over < -kneeDb { return 0 }
        if 2 * abs(over) <= kneeDb {
            let t = over + kneeDb / 2
            return (1 / r - 1) * t * t / (2 * kneeDb)
        }
        return (1 / r - 1) * over
    }

    public var isActive: Bool { thresholdDb < -0.05 && ratio > 1.01 || abs(makeupDb) > 0.01 }

    @inline(__always)
    public mutating func process(_ left: Float, _ right: Float) -> (Float, Float) {
        let peak = max(abs(left), abs(right))
        let inDb = DSP.gainToDb(peak)
        let coeff = inDb > envelopeDb ? attackCoeff : releaseCoeff
        envelopeDb = inDb + coeff * (envelopeDb - inDb)
        let gr = gainReduction(forInputDb: envelopeDb)
        currentGainReductionDb = gr
        let g = DSP.dbToGain(gr + makeupDb)
        return (left * g, right * g)
    }
}
