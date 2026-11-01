import Foundation

/// Dreiband-EQ: Low-Shelf (120 Hz), Peaking (variabel), High-Shelf (6 kHz).
public struct ThreeBandEQ {
    private var low = Biquad()
    private var mid = Biquad()
    private var high = Biquad()
    private var lastLow: Double = .nan, lastMid: Double = .nan, lastHigh: Double = .nan, lastFreq: Double = .nan
    private var sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        configure(lowDb: 0, midDb: 0, highDb: 0, midFrequency: 1000)
    }

    public mutating func configure(lowDb: Double, midDb: Double, highDb: Double, midFrequency: Double) {
        if lowDb != lastLow {
            low.configure(kind: .lowShelf, frequency: 120, q: 0.707, gainDb: lowDb, sampleRate: sampleRate)
            lastLow = lowDb
        }
        if midDb != lastMid || midFrequency != lastFreq {
            mid.configure(kind: .peaking, frequency: midFrequency, q: 0.9, gainDb: midDb, sampleRate: sampleRate)
            lastMid = midDb
            lastFreq = midFrequency
        }
        if highDb != lastHigh {
            high.configure(kind: .highShelf, frequency: 6000, q: 0.707, gainDb: highDb, sampleRate: sampleRate)
            lastHigh = highDb
        }
    }

    public mutating func reset() { low.reset(); mid.reset(); high.reset() }

    public var isFlat: Bool { low.isIdentity && mid.isIdentity && high.isIdentity }

    @inline(__always)
    public mutating func process(_ left: Float, _ right: Float) -> (Float, Float) {
        var (l, r) = (left, right)
        if !low.isIdentity { (l, r) = low.process(l, r) }
        if !mid.isIdentity { (l, r) = mid.process(l, r) }
        if !high.isIdentity { (l, r) = high.process(l, r) }
        return (l, r)
    }
}
