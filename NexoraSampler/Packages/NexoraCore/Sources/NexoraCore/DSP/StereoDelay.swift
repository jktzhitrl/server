import Foundation

/// Stereo-Delay mit Feedback, optionalem Ping-Pong und Dämpfung im Rückkopplungsweg.
/// Der Puffer wird einmalig bei der Initialisierung angelegt (echtzeitsicher).
public final class StereoDelay {
    public static let maximumSeconds: Double = 2.5

    private let capacity: Int
    private let bufferL: UnsafeMutablePointer<Float>
    private let bufferR: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    private let sampleRate: Double
    private var smoothedDelay: SmoothedValue
    private var dampL: Float = 0, dampR: Float = 0
    private var primed = false

    public var delaySeconds: Double = 0.375
    public var feedback: Float = 0.35
    public var pingPong: Bool = true
    /// 0 = hell, 1 = stark gedämpft
    public var damping: Float = 0.3

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        capacity = Int(Self.maximumSeconds * sampleRate) + 4
        bufferL = .allocate(capacity: capacity)
        bufferR = .allocate(capacity: capacity)
        bufferL.initialize(repeating: 0, count: capacity)
        bufferR.initialize(repeating: 0, count: capacity)
        smoothedDelay = SmoothedValue(value: Float(0.375 * sampleRate), timeSeconds: 0.08, sampleRate: sampleRate)
    }

    deinit {
        bufferL.deallocate()
        bufferR.deallocate()
    }

    public func reset() {
        bufferL.update(repeating: 0, count: capacity)
        bufferR.update(repeating: 0, count: capacity)
        dampL = 0; dampR = 0
        primed = false
    }

    @inline(__always)
    private func read(_ buffer: UnsafeMutablePointer<Float>, delay: Float) -> Float {
        var pos = Float(writeIndex) - delay
        if pos < 0 { pos += Float(capacity) }
        let i0 = Int(pos)
        let frac = pos - Float(i0)
        let i1 = (i0 + 1) % capacity
        return buffer[i0 % capacity] * (1 - frac) + buffer[i1] * frac
    }

    /// Verarbeitet das Send-Signal und schreibt ausschließlich das Wet-Signal nach `outL/outR`.
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                        outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>, count: Int) {
        smoothedDelay.target = Float(DSP.clamp(delaySeconds, 0.001, Self.maximumSeconds - 0.01) * sampleRate)
        if !primed {
            primed = true
            smoothedDelay.reset(to: smoothedDelay.target)
        }
        let fb = DSP.clamp(feedback, 0, 0.95)
        let dampCoeff = DSP.clamp(damping, 0, 0.95)
        for i in 0..<count {
            let d = smoothedDelay.next()
            let yL = read(bufferL, delay: d)
            let yR = read(bufferR, delay: d)
            dampL = yL + dampCoeff * (dampL - yL)
            dampR = yR + dampCoeff * (dampR - yR)
            let fbL = DSP.flushDenormal(dampL * fb)
            let fbR = DSP.flushDenormal(dampR * fb)
            if pingPong {
                // Eingang mono summiert in den linken Kanal, Rückkopplung kreuzweise.
                bufferL[writeIndex] = (inL[i] + inR[i]) * 0.5 + fbR
                bufferR[writeIndex] = fbL
            } else {
                bufferL[writeIndex] = inL[i] + fbL
                bufferR[writeIndex] = inR[i] + fbR
            }
            outL[i] = yL
            outR[i] = yR
            writeIndex += 1
            if writeIndex >= capacity { writeIndex = 0 }
        }
    }
}

/// Moduliertes kurzes Delay – erzeugt echtes Tonhöhen-Vibrato auf dem Master-Bus.
public final class VibratoProcessor {
    private let capacity: Int
    private let bufferL: UnsafeMutablePointer<Float>
    private let bufferR: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    private let sampleRate: Double

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        capacity = Int(0.03 * sampleRate) + 4
        bufferL = .allocate(capacity: capacity)
        bufferR = .allocate(capacity: capacity)
        bufferL.initialize(repeating: 0, count: capacity)
        bufferR.initialize(repeating: 0, count: capacity)
    }

    deinit {
        bufferL.deallocate()
        bufferR.deallocate()
    }

    public func reset() {
        bufferL.update(repeating: 0, count: capacity)
        bufferR.update(repeating: 0, count: capacity)
    }

    /// - Parameter modulation: -1 ... 1 (LFO-Wert × Tiefe)
    @inline(__always)
    public func process(_ left: Float, _ right: Float, modulation: Float) -> (Float, Float) {
        bufferL[writeIndex] = left
        bufferR[writeIndex] = right
        let base = Float(0.006 * sampleRate)
        let delay = base + modulation * Float(0.005 * sampleRate)
        var pos = Float(writeIndex) - delay
        if pos < 0 { pos += Float(capacity) }
        let i0 = Int(pos) % capacity
        let i1 = (i0 + 1) % capacity
        let frac = pos - floorf(pos)
        let l = bufferL[i0] * (1 - frac) + bufferL[i1] * frac
        let r = bufferR[i0] * (1 - frac) + bufferR[i1] * frac
        writeIndex += 1
        if writeIndex >= capacity { writeIndex = 0 }
        return (l, r)
    }
}
