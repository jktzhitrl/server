import XCTest
@testable import NexoraCore

final class SequencerTests: XCTestCase {
    private let sr = 44_100.0

    private func sequencedEngine(pattern: SequencerPattern, bpm: Double = 120, swing: Double = 50,
                                 pads: [Int] = [0], settings: PadSettings = neutralPadSettings()) -> SamplerEngine {
        let e = makeNeutralEngine()
        for pad in pads {
            e.send(.setSample(pad: pad, sample: SampleBuffer(name: "DC", sampleRate: sr, channels: [TestAudio.constant(0.5, frames: 400)])))
            e.send(.setPadSettings(pad: pad, settings: settings))
        }
        e.send(.setTempo(bpm: bpm, swing: swing))
        e.send(.setPattern(slot: 0, pattern: PatternSnapshot(pattern)))
        e.send(.selectPattern(slot: 0, immediately: true))
        return e
    }

    func testStepTimingIsSampleAccurate() {
        var p = SequencerPattern(name: "T")
        for s in [0, 4, 8, 12] { p[0, s] = SequencerStep(active: true, velocity: 1) }
        let e = sequencedEngine(pattern: p)
        e.send(.transport(.play))
        // 120 BPM → 16tel = 5512,5 Samples; Viertel = 22050 Samples
        let out = renderEngine(e, frames: 22_050 * 8 - 100, block: 333).left
        let found = onsets(out)
        XCTAssertEqual(found.count, 8)
        for (k, onset) in found.enumerated() {
            XCTAssertEqual(Double(onset), Double(k) * 22_050, accuracy: 1.0, "Schritt \(k * 4)")
        }
    }

    func testEverySixteenthWithFractionalStepLength() {
        var p = SequencerPattern(name: "T")
        for s in 0..<16 { p[0, s] = SequencerStep(active: true, velocity: 1) }
        let e = sequencedEngine(pattern: p)
        e.send(.transport(.play))
        let out = renderEngine(e, frames: 88_150, block: 512).left
        let found = onsets(out, minimumGap: 100)
        XCTAssertEqual(found.count, 16)
        for (k, onset) in found.enumerated() {
            XCTAssertEqual(Double(onset), (Double(k) * 5512.5).rounded(.up), accuracy: 1.0)
        }
    }

    func testSwingDelaysOddSteps() {
        var p = SequencerPattern(name: "T")
        p[0, 0] = SequencerStep(active: true)
        p[0, 1] = SequencerStep(active: true)
        let e = sequencedEngine(pattern: p, swing: 66.6667)
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: 20_000).left)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Double(found[1]), 5512.5 * 4 / 3, accuracy: 2, "Triolen-Swing")
    }

    func testMicroTimingOffset() {
        var p = SequencerPattern(name: "T")
        p[0, 4] = SequencerStep(active: true, velocity: 1, offset: -0.25)
        let e = sequencedEngine(pattern: p)
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: 40_000).left)
        XCTAssertEqual(Double(found.first ?? -1), 5512.5 * 3.75, accuracy: 2)
    }

    func testTempoChangesStepLength() {
        var p = SequencerPattern(name: "T")
        p[0, 0] = SequencerStep(active: true)
        p[0, 4] = SequencerStep(active: true)
        let e = sequencedEngine(pattern: p, bpm: 60)
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: 60_000).left)
        XCTAssertEqual(Double(found[1]), 44_100, accuracy: 1)
    }

    func testPatternSwitchHappensAtBarEnd() {
        var a = SequencerPattern(name: "A")
        a[0, 0] = SequencerStep(active: true)
        var b = SequencerPattern(name: "B")
        b[1, 0] = SequencerStep(active: true)
        let e = sequencedEngine(pattern: a, pads: [0, 1])
        var s1 = neutralPadSettings()
        s1.pan = 1 // Pad 2 nur rechts hörbar
        var s0 = neutralPadSettings()
        s0.pan = -1 // Pad 1 nur links
        e.send(.setPadSettings(pad: 0, settings: s0))
        e.send(.setPadSettings(pad: 1, settings: s1))
        e.send(.setPattern(slot: 1, pattern: PatternSnapshot(b)))
        e.send(.transport(.play))
        _ = renderEngine(e, frames: 30_000)
        e.send(.selectPattern(slot: 1, immediately: false))
        XCTAssertEqual(e.sequencerSlot, 0)
        let rest = renderEngine(e, frames: 88_200 * 2 - 30_000)
        let leftOnsets = onsets(rest.left)
        let rightOnsets = onsets(rest.right)
        XCTAssertEqual(leftOnsets.count, 0, "Pattern A spielt nach dem Wechsel nicht mehr")
        XCTAssertEqual(rightOnsets.count, 1)
        XCTAssertEqual(Double(rightOnsets[0] + 30_000), 88_200, accuracy: 1, "Wechsel exakt am Taktbeginn")
        var changed = false
        e.pollEvents { _ in changed = true }
        XCTAssertEqual(e.sequencerSlot, 1)
        _ = changed
    }

    func testMuteAndSolo() {
        var p = SequencerPattern(name: "T")
        p[0, 0] = SequencerStep(active: true)
        p[1, 8] = SequencerStep(active: true)
        let muted = sequencedEngine(pattern: p, pads: [0, 1])
        muted.send(.setTrackStates(mutes: 0b11, solos: 0))
        muted.send(.transport(.play))
        XCTAssertEqual(onsets(renderEngine(muted, frames: 88_200).left).count, 0)

        let solo = sequencedEngine(pattern: p, pads: [0, 1])
        solo.send(.setTrackStates(mutes: 0, solos: 0b10))
        solo.send(.transport(.play))
        let found = onsets(renderEngine(solo, frames: 88_200).left)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(Double(found[0]), 5512.5 * 8, accuracy: 1)
    }

    func testPauseResumeAndStop() {
        var p = SequencerPattern(name: "T")
        p[0, 8] = SequencerStep(active: true)
        let e = sequencedEngine(pattern: p)
        e.send(.transport(.play))
        _ = renderEngine(e, frames: 22_050) // 4 Schritte
        e.send(.transport(.pause))
        let paused = renderEngine(e, frames: 44_100).left
        XCTAssertEqual(onsets(paused).count, 0)
        XCTAssertEqual(e.status.transport, .paused)
        XCTAssertEqual(e.sequencerPosition, 4, accuracy: 0.01)
        e.send(.transport(.play))
        let resumed = onsets(renderEngine(e, frames: 30_000).left)
        XCTAssertEqual(Double(resumed.first ?? -1), 22_050, accuracy: 1, "Fortsetzung an gleicher Stelle")
        e.send(.transport(.stop))
        _ = renderEngine(e, frames: 10)
        XCTAssertEqual(e.sequencerPosition, 0)
        XCTAssertEqual(e.status.transport, .stopped)
    }

    func testGateLengthForGatePads() {
        var s = neutralPadSettings()
        s.playMode = .gate
        s.release = 0.005
        var p = SequencerPattern(name: "T")
        p[0, 0] = SequencerStep(active: true)
        p.gates[0] = 2
        let e = makeNeutralEngine()
        e.send(.setSample(pad: 0, sample: SampleBuffer(name: "Long", sampleRate: sr, channels: [TestAudio.constant(0.5, frames: 88_200)])))
        e.send(.setPadSettings(pad: 0, settings: s))
        e.send(.setPattern(slot: 0, pattern: PatternSnapshot(p)))
        e.send(.transport(.play))
        let out = renderEngine(e, frames: 20_000).left
        XCTAssertEqual(out[10_000], 0.5, accuracy: 0.01)
        XCTAssertEqual(out[11_025 + 1_500], 0, accuracy: 0.001, "Note endet nach 2 Schritten")
    }

    func testLiveRecordingReportsPosition() {
        let e = sequencedEngine(pattern: SequencerPattern(name: "Empty"))
        e.send(.setRecording(true))
        e.send(.transport(.play))
        _ = renderEngine(e, frames: Int(5512.5 * 6))
        e.send(.noteOn(pad: 0, velocity: 0.9))
        _ = renderEngine(e, frames: 256)
        var hits: [(Int, Double)] = []
        e.pollEvents { event in
            if case let .recordedHit(pad, _, _, position, length) = event {
                XCTAssertEqual(length, 16)
                hits.append((pad, position))
            }
        }
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.0, 0)
        XCTAssertEqual(hits.first?.1 ?? -1, 6, accuracy: 0.1)
        let placement = Quantizer.place(position: hits[0].1, length: 16, mode: .sixteenth)
        XCTAssertEqual(placement.step, 6)
    }

    func testMetronomeClicksOnBeats() {
        let e = sequencedEngine(pattern: SequencerPattern(name: "Empty"))
        e.send(.setMetronome(true))
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: 88_200).left)
        XCTAssertEqual(found.count, 4)
    }

    func testQuantizerPlacement() {
        XCTAssertEqual(Quantizer.place(position: 3.4, length: 16, mode: .sixteenth), .init(step: 3, offset: 0))
        XCTAssertEqual(Quantizer.place(position: 3.6, length: 16, mode: .sixteenth), .init(step: 4, offset: 0))
        XCTAssertEqual(Quantizer.place(position: 3.1, length: 16, mode: .eighth), .init(step: 4, offset: 0))
        XCTAssertEqual(Quantizer.place(position: 13.9, length: 16, mode: .quarter), .init(step: 12, offset: 0))
        XCTAssertEqual(Quantizer.place(position: 14.5, length: 16, mode: .quarter), .init(step: 0, offset: 0))
        XCTAssertEqual(Quantizer.place(position: 15.8, length: 16, mode: .sixteenth).step, 0, "Wrap-around ans Pattern-Ende")
        let free = Quantizer.place(position: 4.2, length: 16, mode: .off)
        XCTAssertEqual(free.step, 4)
        XCTAssertEqual(free.offset, 0.2, accuracy: 0.0001)
    }

    func testQuantizePatternRemovesOffsets() {
        var p = SequencerPattern(name: "T")
        p[2, 5] = SequencerStep(active: true, velocity: 0.7, offset: 0.3)
        p[2, 9] = SequencerStep(active: true, velocity: 0.7, offset: -0.4)
        let q16 = Quantizer.quantize(p, mode: .sixteenth)
        XCTAssertTrue(q16[2, 5].active)
        XCTAssertEqual(q16[2, 5].offset, 0)
        XCTAssertTrue(q16[2, 9].active)
        let q4 = Quantizer.quantize(p, mode: .quarter)
        XCTAssertTrue(q4[2, 4].active)
        XCTAssertTrue(q4[2, 8].active)
        XCTAssertFalse(q4[2, 5].active)
    }

    func testPatternNormalizationAndToggle() {
        var p = SequencerPattern(name: "T")
        p.steps = [[SequencerStep(active: true)]]
        p.gates = []
        p.normalize()
        XCTAssertEqual(p.steps.count, 16)
        XCTAssertEqual(p.steps[0].count, 16)
        XCTAssertEqual(p.gates.count, 16)
        p.toggle(track: 3, step: 7)
        XCTAssertTrue(p[3, 7].active)
        p.toggle(track: 3, step: 7)
        XCTAssertFalse(p[3, 7].active)
    }

    func testShorterPatternLengthLoops() {
        var p = SequencerPattern(name: "T", length: 4)
        p[0, 0] = SequencerStep(active: true)
        let e = sequencedEngine(pattern: p)
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: 88_200).left)
        XCTAssertEqual(found.count, 4, "4-Schritt-Pattern wiederholt sich jedes Viertel")
    }
}
