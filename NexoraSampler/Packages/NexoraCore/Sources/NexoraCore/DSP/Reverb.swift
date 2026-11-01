import Foundation

/// Algorithmischer Stereo-Hall nach dem Freeverb-Prinzip (8 parallele gedämpfte
/// Kammfilter + 4 serielle Allpässe je Kanal), auf die Abtastrate skaliert.
public final class Reverb {
    private struct Comb {
        let buffer: UnsafeMutablePointer<Float>
        let size: Int
        var index = 0
        var store: Float = 0

        init(size: Int) {
            self.size = max(size, 1)
            buffer = .allocate(capacity: self.size)
            buffer.initialize(repeating: 0, count: self.size)
        }

        @inline(__always)
        mutating func process(_ input: Float, feedback: Float, damp: Float) -> Float {
            let output = buffer[index]
            store = DSP.flushDenormal(output * (1 - damp) + store * damp)
            buffer[index] = input + store * feedback
            index += 1
            if index >= size { index = 0 }
            return output
        }

        mutating func clear() {
            buffer.update(repeating: 0, count: size)
            store = 0
        }
    }

    private struct Allpass {
        let buffer: UnsafeMutablePointer<Float>
        let size: Int
        var index = 0

        init(size: Int) {
            self.size = max(size, 1)
            buffer = .allocate(capacity: self.size)
            buffer.initialize(repeating: 0, count: self.size)
        }

        @inline(__always)
        mutating func process(_ input: Float) -> Float {
            let buffered = buffer[index]
            let output = buffered - input
            buffer[index] = DSP.flushDenormal(input + buffered * 0.5)
            index += 1
            if index >= size { index = 0 }
            return output
        }

        mutating func clear() { buffer.update(repeating: 0, count: size) }
    }

    private static let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTunings = [556, 441, 341, 225]
    private static let stereoSpread = 23

    private var combsL: [Comb]
    private var combsR: [Comb]
    private var allpassL: [Allpass]
    private var allpassR: [Allpass]

    /// 0 ... 1
    public var roomSize: Float = 0.7
    /// 0 ... 1
    public var damping: Float = 0.4
    /// 0 ... 1
    public var width: Float = 1

    public init(sampleRate: Double) {
        let scale = sampleRate / 44_100
        combsL = Self.combTunings.map { Comb(size: Int(Double($0) * scale)) }
        combsR = Self.combTunings.map { Comb(size: Int(Double($0 + Self.stereoSpread) * scale)) }
        allpassL = Self.allpassTunings.map { Allpass(size: Int(Double($0) * scale)) }
        allpassR = Self.allpassTunings.map { Allpass(size: Int(Double($0 + Self.stereoSpread) * scale)) }
    }

    deinit {
        for c in combsL { c.buffer.deallocate() }
        for c in combsR { c.buffer.deallocate() }
        for a in allpassL { a.buffer.deallocate() }
        for a in allpassR { a.buffer.deallocate() }
    }

    public func reset() {
        for i in combsL.indices { combsL[i].clear(); combsR[i].clear() }
        for i in allpassL.indices { allpassL[i].clear(); allpassR[i].clear() }
    }

    /// Schreibt ausschließlich das Wet-Signal.
    public func process(inL: UnsafePointer<Float>, inR: UnsafePointer<Float>,
                        outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>, count: Int) {
        let feedback = DSP.clamp(roomSize, 0, 1) * 0.28 + 0.7
        let damp = DSP.clamp(damping, 0, 1) * 0.4
        let w = DSP.clamp(width, 0, 1)
        let wet1 = (w / 2 + 0.5)
        let wet2 = (1 - w) / 2
        let gain: Float = 0.015
        let combCount = combsL.count
        let allpassCount = allpassL.count
        combsL.withUnsafeMutableBufferPointer { cl in
            combsR.withUnsafeMutableBufferPointer { cr in
                allpassL.withUnsafeMutableBufferPointer { al in
                    allpassR.withUnsafeMutableBufferPointer { ar in
                        for i in 0..<count {
                            let input = (inL[i] + inR[i]) * gain
                            var sL: Float = 0, sR: Float = 0
                            for c in 0..<combCount {
                                sL += cl[c].process(input, feedback: feedback, damp: damp)
                                sR += cr[c].process(input, feedback: feedback, damp: damp)
                            }
                            for a in 0..<allpassCount {
                                sL = al[a].process(sL)
                                sR = ar[a].process(sR)
                            }
                            outL[i] = (sL * wet1 + sR * wet2) * 3
                            outR[i] = (sR * wet1 + sL * wet2) * 3
                        }
                    }
                }
            }
        }
    }
}
