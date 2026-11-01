import Foundation

/// Dekodierte Audiodaten eines Samples (Float32, nicht verschachtelt, stereo).
/// Mono-Samples werden auf beide Kanäle verteilt. Der Speicher ist unveränderlich,
/// sodass der Audio-Thread ohne Synchronisation lesen kann.
public final class SampleBuffer: @unchecked Sendable {
    public let id = UUID()
    public let name: String
    public let sampleRate: Double
    public let frameCount: Int
    /// Kanalzahl der Quelle (1 oder 2)
    public let sourceChannelCount: Int
    /// Ursprungsdatei (falls aus einer Datei geladen)
    public let sourceURL: URL?

    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    private let ownsRight: Bool

    /// - Parameter channels: Ein oder mehr Kanäle gleicher Länge. Bei mehr als zwei Kanälen
    ///   werden die ersten beiden verwendet.
    public init(name: String, sampleRate: Double, channels: [[Float]], sourceURL: URL? = nil) {
        self.name = name
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        self.sourceURL = sourceURL
        let count = max(channels.first?.count ?? 0, 1)
        frameCount = count
        sourceChannelCount = max(1, min(channels.count, 2))
        func makeChannel(_ data: [Float]?) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            if let data, !data.isEmpty {
                data.withUnsafeBufferPointer { src in
                    p.update(from: src.baseAddress!, count: min(src.count, count))
                }
            }
            return p
        }
        let l = makeChannel(channels.first)
        left = l
        if channels.count >= 2 {
            right = makeChannel(channels[1])
            ownsRight = true
        } else {
            right = l
            ownsRight = false
        }
    }

    deinit {
        left.deallocate()
        if ownsRight { right.deallocate() }
    }

    public var duration: Double { Double(frameCount) / sampleRate }
    public var isStereo: Bool { sourceChannelCount == 2 }

    /// Kopie der Kanaldaten (z. B. zum Schreiben in eine Datei).
    public func channelData() -> [[Float]] {
        let l = Array(UnsafeBufferPointer(start: left, count: frameCount))
        if !isStereo { return [l] }
        return [l, Array(UnsafeBufferPointer(start: right, count: frameCount))]
    }

    /// Wellenform-Übersicht (Spitzenwerte beider Kanäle) für die Anzeige.
    public func overview(bins: Int) -> [Float] {
        let l = VectorOps.overview(left, count: frameCount, bins: bins)
        guard isStereo else { return l }
        let r = VectorOps.overview(right, count: frameCount, bins: bins)
        return zip(l, r).map { max($0, $1) }
    }

    public var peak: Float {
        max(VectorOps.peak(left, count: frameCount), VectorOps.peak(right, count: frameCount))
    }

    /// Lesezugriff auf einen Frame mit kubischer Interpolation.
    @inline(__always)
    func read(at position: Double) -> (Float, Float) {
        let n = frameCount
        let i = Int(position.rounded(.down))
        let t = Float(position - Double(i))
        let i0 = min(max(i, 0), n - 1)
        let im1 = max(i0 - 1, 0)
        let i1 = min(i0 + 1, n - 1)
        let i2 = min(i0 + 2, n - 1)
        let l = DSP.hermite(left[im1], left[i0], left[i1], left[i2], t)
        if right == left { return (l, l) }
        let r = DSP.hermite(right[im1], right[i0], right[i1], right[i2], t)
        return (l, r)
    }
}
