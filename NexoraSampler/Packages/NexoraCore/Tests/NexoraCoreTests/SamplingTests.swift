import XCTest
@testable import NexoraCore

/// Tests für Slice, Aufnahme (Sampling) und Resampling.
final class SamplingTests: XCTestCase {
    private let sr = 44_100.0

    /// Vier abklingende Anschläge an bekannten Positionen.
    private func drumLoop(hits: [Int], frames: Int, amplitude: [Float]? = nil) -> [Float] {
        var x = [Float](repeating: 0, count: frames)
        for (k, h) in hits.enumerated() {
            let a = amplitude?[k] ?? 0.8
            for i in 0..<min(8_000, frames - h) {
                x[h + i] += a * expf(-Float(i) / 1_500) * sinf(Float(i) * 0.3)
            }
        }
        return x
    }

    func testEqualSlicesCoverRegion() {
        let s = SampleSlicer.slices(left: [Float](repeating: 0.1, count: 1000), right: nil, sampleRate: sr,
                                    mode: .equal(count: 4), regionStart: 0.2, regionEnd: 0.6)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s[0].start, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s[1].start, 0.3, accuracy: 1e-9)
        XCTAssertEqual(s[3].end, 0.6, accuracy: 1e-9)
    }

    func testTransientSlicesFindHits() {
        let hits = [0, 11_025, 22_050, 33_075]
        let x = drumLoop(hits: hits, frames: 44_100)
        let s = SampleSlicer.slices(left: x, right: nil, sampleRate: sr, mode: .transients(sensitivity: 0.5, maxSlices: 16))
        XCTAssertEqual(s.count, 4)
        for (slice, hit) in zip(s, hits) {
            XCTAssertEqual(slice.start * 44_100, Double(hit), accuracy: 300, "Slice bei \(hit)")
        }
    }

    func testSensitivityControlsQuietHits() {
        let hits = [0, 11_025, 22_050, 33_075]
        let x = drumLoop(hits: hits, frames: 44_100, amplitude: [0.9, 0.9, 0.06, 0.9])
        let low = SampleSlicer.slices(left: x, right: nil, sampleRate: sr, mode: .transients(sensitivity: 0, maxSlices: 16))
        let high = SampleSlicer.slices(left: x, right: nil, sampleRate: sr, mode: .transients(sensitivity: 1, maxSlices: 16))
        XCTAssertEqual(low.count, 3, "leiser Anschlag wird bei geringer Empfindlichkeit ignoriert")
        XCTAssertEqual(high.count, 4)
    }

    func testMaxSlicesKeepsStrongestHits() {
        let hits = Array(stride(from: 0, to: 40_000, by: 4_000))
        let x = drumLoop(hits: hits, frames: 44_100)
        let s = SampleSlicer.slices(left: x, right: nil, sampleRate: sr, mode: .transients(sensitivity: 0.6, maxSlices: 4))
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.first?.start ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(s.last?.end ?? 0, 1, accuracy: 1e-9)
    }

    func testSilenceGivesSingleSlice() {
        let s = SampleSlicer.slices(left: [Float](repeating: 0, count: 10_000), right: nil, sampleRate: sr,
                                    mode: .transients(sensitivity: 1, maxSlices: 16))
        XCTAssertEqual(s, [SampleSlicer.Slice(start: 0, end: 1)])
    }

    func testPatternStepsFollowSlicePositions() {
        let slices = [SampleSlicer.Slice(start: 0, end: 0.25), .init(start: 0.25, end: 0.5),
                      .init(start: 0.5, end: 0.75), .init(start: 0.75, end: 1)]
        XCTAssertEqual(SampleSlicer.patternSteps(for: slices, length: 16), [0, 4, 8, 12])
        XCTAssertEqual(SampleSlicer.patternSteps(for: slices, length: 2), [0, 1, 1, 1].enumerated().map { min($0.offset, 1) })
    }

    // MARK: Aufnahme

    private func feed(_ r: SampleRecorder, _ x: [Float], block: Int = 512) {
        var i = 0
        while i < x.count {
            let n = min(block, x.count - i)
            x.withUnsafeBufferPointer { r.append(left: $0.baseAddress! + i, right: nil, count: n) }
            i += n
        }
    }

    func testRecorderWithoutThresholdRecordsEverything() {
        let r = SampleRecorder(sampleRate: sr, options: .init(trimTrailingSilence: false))
        XCTAssertEqual(r.state, .recording)
        feed(r, TestAudio.sine(frequency: 440, seconds: 0.5))
        let s = r.finish(name: "Rec")
        XCTAssertEqual(s?.frameCount, 22_050)
        XCTAssertEqual(r.state, .finished)
    }

    func testRecorderThresholdStartsAtSignalWithPreRoll() {
        let r = SampleRecorder(sampleRate: sr, options: .init(thresholdDb: -30, preRollSeconds: 0.01))
        var x = [Float](repeating: 0.0001, count: 30_000)
        for i in 20_000..<30_000 { x[i] = 0.5 }
        feed(r, x, block: 700)
        XCTAssertEqual(r.state, .recording)
        let s = r.finish(name: "Rec")!
        XCTAssertEqual(s.frameCount, 10_000 + 441, accuracy: 2, "Signal + 10 ms Vorlauf")
    }

    func testRecorderStopsAtMaxLength() {
        let r = SampleRecorder(sampleRate: sr, options: .init(maxSeconds: 0.1, trimTrailingSilence: false))
        feed(r, TestAudio.sine(frequency: 440, seconds: 1))
        XCTAssertEqual(r.state, .finished)
        XCTAssertEqual(r.finish(name: "R")?.frameCount, 4_410)
    }

    func testRecorderTrimsTrailingSilenceAndRejectsEmpty() {
        let r = SampleRecorder(sampleRate: sr)
        feed(r, TestAudio.sine(frequency: 440, seconds: 0.2) + [Float](repeating: 0, count: 20_000))
        let s = r.finish(name: "R")!
        XCTAssertLessThan(s.frameCount, 8_820 + 1_000)
        let empty = SampleRecorder(sampleRate: sr)
        feed(empty, [Float](repeating: 0, count: 5_000))
        XCTAssertNil(empty.finish(name: "E"))
    }

    // MARK: Resampling

    func testResamplingRendersPatternIntoSample() throws {
        var doc = ProjectDocument(name: "R")
        doc.master.volume = 1
        doc.pads[0].settings = neutralPadSettings()
        doc.sequencer.patterns[0].length = 8
        doc.sequencer.patterns[0][0, 0] = SequencerStep(active: true, velocity: 1)
        doc.sequencer.patterns[0][0, 4] = SequencerStep(active: true, velocity: 1)
        var samples = [SampleBuffer?](repeating: nil, count: 16)
        samples[0] = SampleBuffer(name: "DC", sampleRate: sr, channels: [TestAudio.constant(0.5, frames: 500)])
        let result = try OfflineRenderer.render(.init(sampleRate: sr, document: doc, samples: samples,
                                                      patternOrder: [0], loops: 1, tailSeconds: 0))
        let buffer = OfflineRenderer.sampleBuffer(from: result, name: "Resample")
        XCTAssertEqual(Double(buffer.frameCount), 8 * 5512.5, accuracy: 2, "genau ein Pattern-Durchlauf")
        XCTAssertEqual(onsets(buffer.channelData()[0]).count, 2)
    }
}
