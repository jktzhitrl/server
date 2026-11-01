import Foundation
@testable import NexoraCore

enum TestAudio {
    static func sine(frequency: Double, seconds: Double, sampleRate: Double = 44_100, amplitude: Float = 0.5) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) * amplitude }
    }

    static func constant(_ value: Float, frames: Int) -> [Float] {
        [Float](repeating: value, count: frames)
    }

    static func rms(_ x: ArraySlice<Float>) -> Float {
        guard !x.isEmpty else { return 0 }
        return sqrtf(x.reduce(0) { $0 + $1 * $1 } / Float(x.count))
    }

    static func rms(_ x: [Float]) -> Float { rms(x[...]) }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NexoraTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Hilfsfunktion: rendert eine Engine für `frames` Frames.
func renderEngine(_ engine: SamplerEngine, frames: Int, block: Int = 256) -> (left: [Float], right: [Float]) {
    var left: [Float] = []
    var right: [Float] = []
    let l = UnsafeMutablePointer<Float>.allocate(capacity: block)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: block)
    defer { l.deallocate(); r.deallocate() }
    var done = 0
    while done < frames {
        let n = min(block, frames - done)
        engine.render(frameCount: n, left: l, right: r)
        left.append(contentsOf: UnsafeBufferPointer(start: l, count: n))
        right.append(contentsOf: UnsafeBufferPointer(start: r, count: n))
        done += n
    }
    return (left, right)
}

/// Engine mit neutralem Master (kein Effekt, Lautstärke 1).
func makeNeutralEngine(sampleRate: Double = 44_100) -> SamplerEngine {
    let engine = SamplerEngine(sampleRate: sampleRate)
    var master = MasterSettings()
    master.volume = 1
    engine.send(.setMaster(master))
    return engine
}

func neutralPadSettings() -> PadSettings {
    var s = PadSettings()
    s.volume = 1
    s.velocitySensitivity = 0
    s.reverbSend = 0
    s.delaySend = 0
    return s
}

/// Indizes, an denen das Signal (nach Stille) einsetzt.
func onsets(_ x: [Float], threshold: Float = 0.001, minimumGap: Int = 200) -> [Int] {
    var result: [Int] = []
    var silentRun = minimumGap
    for (i, v) in x.enumerated() {
        if abs(v) > threshold {
            if silentRun >= minimumGap { result.append(i) }
            silentRun = 0
        } else {
            silentRun += 1
        }
    }
    return result
}
