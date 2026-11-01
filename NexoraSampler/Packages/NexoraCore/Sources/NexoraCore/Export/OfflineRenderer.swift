import Foundation

/// Rendert Patterns offline mit derselben `SamplerEngine`, die auch live spielt.
/// Ergebnis ist damit exakt das Signal, das der Benutzer hört (inkl. aller Effekte).
public enum OfflineRenderer {
    public struct Request: @unchecked Sendable {
        public var sampleRate: Double
        public var document: ProjectDocument
        /// Dekodierte Samples je Pad
        public var samples: [SampleBuffer?]
        /// Abzuspielende Pattern-Slots in Reihenfolge
        public var patternOrder: [Int]
        /// Wiederholungen jedes Patterns
        public var loops: Int
        /// Maximale Ausklingzeit in Sekunden
        public var tailSeconds: Double

        public init(sampleRate: Double, document: ProjectDocument, samples: [SampleBuffer?],
                    patternOrder: [Int], loops: Int, tailSeconds: Double) {
            self.sampleRate = sampleRate
            self.document = document
            self.samples = samples
            self.patternOrder = patternOrder
            self.loops = loops
            self.tailSeconds = tailSeconds
        }
    }

    public struct Result: Sendable {
        public var left: [Float]
        public var right: [Float]
        public var sampleRate: Double
        public var duration: Double { Double(left.count) / sampleRate }
        public var peak: Float { max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0) }
    }

    public struct Cancelled: Error {}

    /// - Parameter progress: Wird mit Werten 0 ... 1 aufgerufen; `false` bricht ab.
    public static func render(_ request: Request, progress: ((Double) -> Bool)? = nil) throws -> Result {
        let doc = request.document
        let engine = SamplerEngine(sampleRate: request.sampleRate)
        for pad in 0..<16 {
            engine.send(.setPadSettings(pad: pad, settings: doc.pads[pad].settings))
            engine.send(.setSample(pad: pad, sample: request.samples.indices.contains(pad) ? request.samples[pad] : nil))
        }
        engine.send(.setMaster(doc.master))
        engine.send(.setEngineSettings(doc.engine))
        engine.send(.setTempo(bpm: doc.bpm, swing: doc.swing))
        engine.send(.setTrackStates(mutes: doc.sequencer.muteMask, solos: doc.sequencer.soloMask))
        engine.send(.setMetronome(false))
        for (slot, pattern) in doc.sequencer.patterns.enumerated() {
            engine.send(.setPattern(slot: slot, pattern: PatternSnapshot(pattern)))
        }

        var order: [Int] = []
        for slot in request.patternOrder where doc.sequencer.patterns.indices.contains(slot) {
            order.append(contentsOf: Array(repeating: slot, count: max(1, request.loops)))
        }
        if order.isEmpty { order = Array(repeating: doc.sequencer.currentPattern, count: max(1, request.loops)) }

        let totalSteps = order.reduce(0) { $0 + doc.sequencer.patterns[$1].length }
        let stepFrames = request.sampleRate * 60 / doc.bpm / 4
        let playFrames = Int((Double(totalSteps) * stepFrames).rounded(.up))
        let maxTailFrames = Int(request.tailSeconds * request.sampleRate)
        let block = 512

        engine.send(.selectPattern(slot: order[0], immediately: true))
        engine.send(.transport(.play))

        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(playFrames + maxTailFrames)
        right.reserveCapacity(playFrames + maxTailFrames)
        let bufL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let bufR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { bufL.deallocate(); bufR.deallocate() }

        // Pattern-Kette: Grenzen in Schritten
        var boundaries: [Int] = []
        var acc = 0
        for slot in order { acc += doc.sequencer.patterns[slot].length; boundaries.append(acc) }
        var orderIndex = 0
        var queuedNext = false

        var rendered = 0
        while rendered < playFrames {
            let n = min(block, playFrames - rendered)
            // Nächstes Pattern rechtzeitig vormerken (Wechsel erfolgt sample-genau an der Grenze).
            if !queuedNext && orderIndex + 1 < order.count {
                let pos = engine.sequencerPosition
                let start = orderIndex == 0 ? 0 : boundaries[orderIndex - 1]
                if pos >= Double(start) + 0.01 {
                    engine.send(.selectPattern(slot: order[orderIndex + 1], immediately: false))
                    queuedNext = true
                }
            }
            engine.render(frameCount: n, left: bufL, right: bufR)
            left.append(contentsOf: UnsafeBufferPointer(start: bufL, count: n))
            right.append(contentsOf: UnsafeBufferPointer(start: bufR, count: n))
            rendered += n
            if queuedNext && engine.sequencerPosition >= Double(boundaries[orderIndex]) {
                orderIndex += 1
                queuedNext = false
            }
            if let progress, !progress(Double(rendered) / Double(playFrames + maxTailFrames / 2)) {
                throw Cancelled()
            }
        }

        engine.send(.transport(.stop))

        // Ausklingen bis zur Stille (−90 dB über 200 ms) oder bis zur maximalen Tail-Länge.
        let silenceThreshold: Float = 0.000_03
        let silenceFramesNeeded = Int(0.2 * request.sampleRate)
        var silentFrames = 0
        var tail = 0
        while tail < maxTailFrames {
            let n = min(block, maxTailFrames - tail)
            engine.render(frameCount: n, left: bufL, right: bufR)
            left.append(contentsOf: UnsafeBufferPointer(start: bufL, count: n))
            right.append(contentsOf: UnsafeBufferPointer(start: bufR, count: n))
            tail += n
            let pk = max(VectorOps.peak(bufL, count: n), VectorOps.peak(bufR, count: n))
            silentFrames = pk < silenceThreshold ? silentFrames + n : 0
            if silentFrames >= silenceFramesNeeded { break }
            if let progress, !progress(min(1, Double(rendered + tail) / Double(playFrames + maxTailFrames / 2))) {
                throw Cancelled()
            }
        }
        // Abschließende Stille entfernen (bis auf 50 ms)
        if silentFrames > 0 {
            let keep = max(left.count - silentFrames + Int(0.05 * request.sampleRate), playFrames)
            if keep < left.count {
                left.removeLast(left.count - keep)
                right.removeLast(right.count - keep)
            }
        }
        engine.drainGarbage()
        return Result(left: left, right: right, sampleRate: request.sampleRate)
    }

    /// Normalisiert auf −0,3 dBFS.
    public static func normalize(_ result: inout Result) {
        let pk = result.peak
        guard pk > 0.0001 else { return }
        let g = DSP.dbToGain(-0.3) / pk
        result.left = result.left.map { $0 * g }
        result.right = result.right.map { $0 * g }
    }
}
