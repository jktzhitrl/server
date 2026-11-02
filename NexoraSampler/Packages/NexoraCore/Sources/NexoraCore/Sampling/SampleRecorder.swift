import Foundation

/// Nimmt Audio (Mikrofon, Line-In oder den eigenen Ausgang beim Resampling) als neues Sample auf.
///
/// `append` wird aus dem Aufnahme-Thread (Audio-Tap) aufgerufen, alle übrigen Methoden vom
/// Haupt-Thread. Mit Schwelle wartet der Rekorder, bis das Signal sie überschreitet, und
/// behält dabei einen kurzen Vorlauf, damit der Anschlag nicht abgeschnitten wird.
public final class SampleRecorder: @unchecked Sendable {
    public enum State: Equatable, Sendable { case armed, recording, finished }

    public struct Options: Sendable {
        /// Startschwelle in dBFS; `nil` = sofort aufnehmen
        public var thresholdDb: Double?
        /// Maximale Länge in Sekunden
        public var maxSeconds: Double
        /// Vorlauf vor dem Überschreiten der Schwelle
        public var preRollSeconds: Double
        /// Stille am Ende (unter −60 dBFS) entfernen
        public var trimTrailingSilence: Bool

        public init(thresholdDb: Double? = nil, maxSeconds: Double = 600, preRollSeconds: Double = 0.01,
                    trimTrailingSilence: Bool = true) {
            self.thresholdDb = thresholdDb
            self.maxSeconds = maxSeconds
            self.preRollSeconds = preRollSeconds
            self.trimTrailingSilence = trimTrailingSilence
        }
    }

    public let sampleRate: Double
    public let options: Options
    private let lock = NSLock()
    private var left: [Float] = []
    private var right: [Float] = []
    private var preL: [Float] = []
    private var preR: [Float] = []
    private var stereo = false
    private var _state: State
    private var _level: Float = 0
    private let maxFrames: Int
    private let preRollFrames: Int
    private let threshold: Float

    public init(sampleRate: Double, options: Options = Options()) {
        self.sampleRate = sampleRate
        self.options = options
        maxFrames = max(1, Int(options.maxSeconds * sampleRate))
        preRollFrames = max(0, Int(options.preRollSeconds * sampleRate))
        threshold = options.thresholdDb.map { DSP.dbToGain(Float($0)) } ?? 0
        _state = options.thresholdDb == nil ? .recording : .armed
        left.reserveCapacity(min(maxFrames, Int(sampleRate * 30)))
        right.reserveCapacity(min(maxFrames, Int(sampleRate * 30)))
    }

    public var state: State { lock.lock(); defer { lock.unlock() }; return _state }
    /// Spitzenpegel des zuletzt empfangenen Blocks (0 ... 1)
    public var level: Float { lock.lock(); defer { lock.unlock() }; return _level }
    public var recordedSeconds: Double { lock.lock(); defer { lock.unlock() }; return Double(left.count) / sampleRate }

    /// Hängt einen Block an. `right == nil` für Mono-Quellen.
    public func append(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>?, count: Int) {
        guard count > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        var peak: Float = 0
        for i in 0..<count { peak = max(peak, abs(l[i]), abs(r?[i] ?? 0)) }
        _level = peak
        if r != nil { stereo = true }
        switch _state {
        case .finished:
            return
        case .armed:
            var firstAbove = -1
            for i in 0..<count where max(abs(l[i]), abs(r?[i] ?? 0)) >= threshold { firstAbove = i; break }
            if firstAbove < 0 {
                preL.append(contentsOf: UnsafeBufferPointer(start: l, count: count))
                preR.append(contentsOf: UnsafeBufferPointer(start: r ?? l, count: count))
                if preL.count > preRollFrames {
                    preL.removeFirst(preL.count - preRollFrames)
                    preR.removeFirst(preR.count - preRollFrames)
                }
                return
            }
            // Vorlauf: Rest des Puffers vor dem Anschlag plus Anfang dieses Blocks
            let lead = min(firstAbove, preRollFrames)
            let fromPre = max(0, preRollFrames - lead)
            left.append(contentsOf: preL.suffix(fromPre))
            right.append(contentsOf: preR.suffix(fromPre))
            preL.removeAll(); preR.removeAll()
            _state = .recording
            appendFrames(l + (firstAbove - lead), r.map { $0 + (firstAbove - lead) }, count - (firstAbove - lead))
        case .recording:
            appendFrames(l, r, count)
        }
    }

    private func appendFrames(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>?, _ count: Int) {
        let n = min(count, maxFrames - left.count)
        guard n > 0 else { _state = .finished; return }
        left.append(contentsOf: UnsafeBufferPointer(start: l, count: n))
        right.append(contentsOf: UnsafeBufferPointer(start: r ?? l, count: n))
        if left.count >= maxFrames { _state = .finished }
    }

    /// Beendet die Aufnahme. Liefert `nil`, wenn nichts aufgenommen wurde.
    public func finish(name: String) -> SampleBuffer? {
        lock.lock()
        _state = .finished
        var l = left, r = right
        let isStereo = stereo
        lock.unlock()
        if options.trimTrailingSilence {
            let floor = DSP.dbToGain(-60)
            var end = l.count
            while end > 0 && abs(l[end - 1]) < floor && abs(r[end - 1]) < floor { end -= 1 }
            if end == 0 { return nil }
            let keep = min(l.count, end + Int(0.02 * sampleRate))
            l.removeLast(l.count - keep)
            r.removeLast(r.count - keep)
        }
        guard l.count > Int(0.005 * sampleRate) else { return nil }
        let channels = isStereo && zip(l, r).contains { $0 != $1 } ? [l, r] : [l]
        return SampleBuffer(name: name, sampleRate: sampleRate, channels: channels)
    }
}
