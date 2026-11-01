import XCTest
@testable import NexoraCore

final class ExportTests: XCTestCase {
    func testWavRoundTripAllBitDepths() throws {
        let left = TestAudio.sine(frequency: 1000, seconds: 0.05, amplitude: 0.7)
        let right = left.map { -$0 * 0.5 }
        for depth in ExportBitDepth.allCases {
            let data = try AudioFileWriter.encode(left: left, right: right, sampleRate: 48_000, format: .wav, bitDepth: depth, dither: false)
            let decoded = try AudioFileReader.decode(data)
            XCTAssertEqual(decoded.sampleRate, 48_000)
            XCTAssertEqual(decoded.channels.count, 2)
            XCTAssertEqual(decoded.channels[0].count, left.count)
            let tolerance: Float = depth == .pcm16 ? 1.0 / 16_000 : (depth == .pcm24 ? 1.0 / 4_000_000 : 0)
            for i in stride(from: 0, to: left.count, by: 37) {
                XCTAssertEqual(decoded.channels[0][i], left[i], accuracy: tolerance)
                XCTAssertEqual(decoded.channels[1][i], right[i], accuracy: tolerance)
            }
        }
    }

    func testWavHeaderLayout() throws {
        let data = try AudioFileWriter.encode(left: [0, 0.5], right: [0, -0.5], sampleRate: 44_100, format: .wav, bitDepth: .pcm16)
        let bytes = [UInt8](data)
        XCTAssertEqual(String(bytes: bytes[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: bytes[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(bytes.count, 44 + 8)
        XCTAssertEqual(Int(bytes[22]), 2, "Stereo")
        XCTAssertEqual(Int(bytes[24]) | Int(bytes[25]) << 8, 44_100 & 0xFFFF)
    }

    func testAiffRoundTripAndExtendedSampleRate() throws {
        for rate in [44_100.0, 48_000.0, 96_000.0, 22_050.0] {
            XCTAssertEqual(AudioFileReader.parseExtended(AudioFileWriter.extended80(rate)), rate, accuracy: 1e-9)
        }
        // 44100 Hz als 80-Bit-Extended laut AIFF-Spezifikation: 40 0E AC 44 00 …
        XCTAssertEqual(Array(AudioFileWriter.extended80(44_100).prefix(4)), [0x40, 0x0E, 0xAC, 0x44])
        let left = TestAudio.sine(frequency: 300, seconds: 0.02)
        let data = try AudioFileWriter.encode(left: left, right: left, sampleRate: 44_100, format: .aiff, bitDepth: .pcm24)
        XCTAssertEqual(String(bytes: [UInt8](data)[0..<4], encoding: .ascii), "FORM")
        let decoded = try AudioFileReader.decode(data)
        XCTAssertEqual(decoded.sampleRate, 44_100)
        XCTAssertEqual(decoded.channels[1][50], left[50], accuracy: 1e-6)
        XCTAssertThrowsError(try AudioFileWriter.encode(left: left, right: left, sampleRate: 44_100, format: .aiff, bitDepth: .float32))
    }

    private func demoRequest(sampleRate: Double, loops: Int = 1) -> OfflineRenderer.Request {
        var doc = ProjectDocument(name: "Export")
        doc.bpm = 120
        var p = SequencerPattern(name: "A")
        p[0, 0] = SequencerStep(active: true, velocity: 1)
        p[0, 8] = SequencerStep(active: true, velocity: 1)
        doc.sequencer.patterns[0] = p
        doc.pads[0].settings = neutralPadSettings()
        doc.master.volume = 1
        var samples = [SampleBuffer?](repeating: nil, count: 16)
        samples[0] = SampleBuffer(name: "DC", sampleRate: 44_100, channels: [TestAudio.constant(0.5, frames: 441)])
        return OfflineRenderer.Request(sampleRate: sampleRate, document: doc, samples: samples,
                                       patternOrder: [0], loops: loops, tailSeconds: 1)
    }

    func testOfflineRenderContainsPatternAtCorrectPositions() throws {
        let result = try OfflineRenderer.render(demoRequest(sampleRate: 44_100, loops: 2))
        let found = onsets(result.left)
        XCTAssertEqual(found.count, 4)
        for (k, onset) in found.enumerated() {
            XCTAssertEqual(Double(onset), Double(k) * 44_100, accuracy: 1)
        }
        XCTAssertGreaterThanOrEqual(result.duration, 4.0)
        XCTAssertLessThan(result.duration, 4.5, "Stille am Ende wird abgeschnitten")
        XCTAssertEqual(result.left[100], 0.5, accuracy: 0.01)
    }

    func testOfflineRenderAt48kHz() throws {
        let result = try OfflineRenderer.render(demoRequest(sampleRate: 48_000))
        XCTAssertEqual(result.sampleRate, 48_000)
        let found = onsets(result.left)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Double(found[1]), 48_000, accuracy: 1)
        // 441 Frames bei 44,1 kHz = 10 ms → bei 48 kHz 480 Frames lang
        let length = result.left[0..<2000].lastIndex(where: { abs($0) > 1e-5 }) ?? 0
        XCTAssertEqual(Double(length), 480, accuracy: 3)
    }

    func testOfflineRenderIsDeterministicAndIncludesEffects() throws {
        var request = demoRequest(sampleRate: 44_100)
        request.document.master.reverbMix = 0.8
        request.document.pads[0].settings.reverbSend = 1
        let a = try OfflineRenderer.render(request)
        let b = try OfflineRenderer.render(request)
        XCTAssertEqual(a.left, b.left)
        // Hallfahne nach dem Sample (10 ms) vorhanden
        XCTAssertGreaterThan(TestAudio.rms(a.left[2_000..<20_000]), 0.0005)
    }

    func testPatternChainExport() throws {
        var request = demoRequest(sampleRate: 44_100)
        var b = SequencerPattern(name: "B", length: 8)
        b[0, 4] = SequencerStep(active: true, velocity: 1)
        request.document.sequencer.patterns[1] = b
        request.patternOrder = [0, 1]
        request.tailSeconds = 0
        let result = try OfflineRenderer.render(request)
        // A: Schritte 0 und 8 (0 s, 1 s); B (8 Schritte) beginnt bei 2 s, Schritt 4 → 2,5 s
        let found = onsets(result.left)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(Double(found[2]), 2.5 * 44_100, accuracy: 1)
        XCTAssertEqual(result.duration, 3.0, accuracy: 0.01)
    }

    func testRenderCancellation() {
        XCTAssertThrowsError(try OfflineRenderer.render(demoRequest(sampleRate: 44_100, loops: 8)) { _ in false })
    }

    func testNormalize() throws {
        var result = try OfflineRenderer.render(demoRequest(sampleRate: 44_100))
        OfflineRenderer.normalize(&result)
        XCTAssertEqual(result.peak, DSP.dbToGain(-0.3), accuracy: 0.001)
    }
}
