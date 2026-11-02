import Foundation

/// Zerlegt ein Sample in Abschnitte (Slices), die auf Pads verteilt werden.
/// Jede Slice ist ein Bereich (Start/Ende, 0 ... 1) innerhalb desselben Samples –
/// dadurch belegt das Slicen keinen zusätzlichen Speicher.
public enum SampleSlicer {
    public enum Mode: Equatable, Sendable {
        /// Gleich lange Abschnitte
        case equal(count: Int)
        /// Abschnitte an erkannten Anschlägen (Transienten)
        /// - sensitivity: 0 (nur deutliche Anschläge) ... 1 (auch leise Anschläge)
        case transients(sensitivity: Double, maxSlices: Int)
    }

    public struct Slice: Equatable, Sendable {
        /// Start und Ende relativ zur Sample-Länge (0 ... 1)
        public var start: Double
        public var end: Double
    }

    public static let maxSlices = 16

    /// Slices innerhalb des Bereichs `regionStart ..< regionEnd` (relativ, 0 ... 1).
    public static func slices(of sample: SampleBuffer, mode: Mode, regionStart: Double = 0, regionEnd: Double = 1) -> [Slice] {
        let left = Array(UnsafeBufferPointer(start: sample.left, count: sample.frameCount))
        let right = sample.isStereo ? Array(UnsafeBufferPointer(start: sample.right, count: sample.frameCount)) : nil
        return slices(left: left, right: right, sampleRate: sample.sampleRate, mode: mode,
                      regionStart: regionStart, regionEnd: regionEnd)
    }

    public static func slices(left: [Float], right: [Float]?, sampleRate: Double, mode: Mode,
                              regionStart: Double = 0, regionEnd: Double = 1) -> [Slice] {
        let a = DSP.clamp(min(regionStart, regionEnd), 0, 1)
        let b = DSP.clamp(max(regionStart, regionEnd), 0, 1)
        guard b - a > 1e-6, !left.isEmpty else { return [Slice(start: 0, end: 1)] }
        var starts: [Double]
        switch mode {
        case .equal(let count):
            let n = DSP.clamp(count, 1, maxSlices)
            starts = (0..<n).map { a + (b - a) * Double($0) / Double(n) }
        case .transients(let sensitivity, let maxCount):
            let frames = left.count
            let from = Int(a * Double(frames)), to = Int(b * Double(frames))
            let onsets = detectOnsets(left: left, right: right, from: from, to: to, sampleRate: sampleRate,
                                      sensitivity: sensitivity, maxCount: DSP.clamp(maxCount, 1, maxSlices))
            starts = [a] + onsets.map { Double($0) / Double(frames) }.filter { $0 > a + 1e-6 && $0 < b - 1e-6 }
        }
        starts.sort()
        var result: [Slice] = []
        for (i, s) in starts.enumerated() {
            let e = i + 1 < starts.count ? starts[i + 1] : b
            if e - s > 1e-6 { result.append(Slice(start: s, end: e)) }
        }
        return result
    }

    /// Anschlagerkennung über den Anstieg der Kurzzeit-Energie.
    /// - Returns: Frame-Positionen der Anschläge (ohne den Bereichsanfang), zeitlich sortiert.
    static func detectOnsets(left: [Float], right: [Float]?, from: Int, to: Int, sampleRate: Double,
                             sensitivity: Double, maxCount: Int) -> [Int] {
        let hop = 256
        let count = (to - from) / hop
        guard count > 4 else { return [] }
        var env = [Float](repeating: 0, count: count)
        for h in 0..<count {
            var sum: Float = 0
            let base = from + h * hop
            for i in base..<min(base + hop, to) {
                let v = right.map { (left[i] + $0[i]) * 0.5 } ?? left[i]
                sum += v * v
            }
            env[h] = sqrtf(sum / Float(hop))
        }
        let maxEnv = env.max() ?? 0
        guard maxEnv > 1e-5 else { return [] }
        let s = DSP.clamp(sensitivity, 0, 1)
        let floor = maxEnv * Float(0.12 - 0.1 * s)
        let ratio = Float(1.6 + (1 - s) * 4.4)
        let minGap = max(1, Int(0.05 * sampleRate) / hop)
        let preRoll = Int(0.002 * sampleRate)
        var candidates: [(frame: Int, strength: Float)] = []
        var last = 0
        for h in 1..<count {
            let lo = max(0, h - 4)
            var avg: Float = 0
            for j in lo..<h { avg += env[j] }
            avg /= Float(h - lo)
            let strength = env[h] / max(avg, floor * 0.5)
            guard env[h] > floor, strength > ratio, h - last >= minGap else { continue }
            // Genaue Position: erstes Sample im Fenster, das deutlich über dem vorherigen Pegel liegt.
            let base = from + h * hop
            var onset = base
            let level = max(avg, 1e-6) * 1.5
            for i in max(from, base - hop)..<min(base + hop, to) {
                let v = right.map { abs((left[i] + $0[i]) * 0.5) } ?? abs(left[i])
                if v > level { onset = i; break }
            }
            candidates.append((max(from, onset - preRoll), strength))
            last = h
        }
        if candidates.count > maxCount - 1 {
            candidates = Array(candidates.sorted { $0.strength > $1.strength }.prefix(max(0, maxCount - 1)))
        }
        return candidates.map(\.frame).sorted()
    }

    /// Schritte, auf die die Slices in einem Pattern der Länge `length` fallen
    /// (das Sample entspricht dabei genau einem Pattern-Durchlauf).
    public static func patternSteps(for slices: [Slice], length: Int) -> [Int] {
        guard let first = slices.first, let last = slices.last else { return [] }
        let span = max(last.end - first.start, 1e-9)
        var used = Set<Int>()
        return slices.map { slice in
            var step = Int(((slice.start - first.start) / span * Double(length)).rounded())
            step = DSP.clamp(step, 0, max(0, length - 1))
            while used.contains(step) && step < length - 1 { step += 1 }
            used.insert(step)
            return step
        }
    }
}
