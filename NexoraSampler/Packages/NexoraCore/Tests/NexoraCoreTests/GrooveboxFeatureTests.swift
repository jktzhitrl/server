import XCTest
@testable import NexoraCore

/// Tests für 64-Schritt-Patterns, Song-Modus und Motion-Sequenz.
final class GrooveboxFeatureTests: XCTestCase {
    private let sr = 44_100.0
    private let stepFrames = 5512.5 // 120 BPM, 16tel

    private func engine(patterns: [SequencerPattern], frames: Int = 400, pads: [Int] = [0, 1],
                        settings: PadSettings = neutralPadSettings()) -> SamplerEngine {
        let e = makeNeutralEngine()
        for pad in pads {
            e.send(.setSample(pad: pad, sample: SampleBuffer(name: "DC", sampleRate: sr, channels: [TestAudio.constant(0.5, frames: frames)])))
            e.send(.setPadSettings(pad: pad, settings: settings))
        }
        e.send(.setTempo(bpm: 120, swing: 50))
        for (i, p) in patterns.enumerated() { e.send(.setPattern(slot: i, pattern: PatternSnapshot(p))) }
        e.send(.selectPattern(slot: 0, immediately: true))
        return e
    }

    // MARK: 64 Schritte

    func testSixtyFourStepPatternPlaysAllBars() {
        var p = SequencerPattern(name: "Long", length: 64)
        for s in [0, 20, 48, 63] { p[0, s] = SequencerStep(active: true, velocity: 1) }
        let e = engine(patterns: [p])
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: Int(stepFrames * 66)).left)
        XCTAssertEqual(found.count, 5, "4 Schläge + Wiederholung bei Schritt 64")
        for (i, s) in [0, 20, 48, 63, 64].enumerated() {
            XCTAssertEqual(Double(found[i]), (Double(s) * stepFrames).rounded(.up), accuracy: 1, "Schritt \(s)")
        }
    }

    func testLengthIsClampedTo64() {
        XCTAssertEqual(SequencerPattern(name: "X", length: 200).length, 64)
        XCTAssertEqual(SequencerPattern.pageCount, 4)
    }

    func testEncodingStoresOnlyUsedPagesAndRoundTrips() throws {
        var p = SequencerPattern(name: "P", length: 16)
        p[3, 2] = SequencerStep(active: true, velocity: 0.5)
        var data = try JSONEncoder().encode(p)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["steps"] as? [[Any]])?.first?.count, 16, "16 Schritte genügen")

        p[3, 40] = SequencerStep(active: true, velocity: 0.7)
        data = try JSONEncoder().encode(p)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["steps"] as? [[Any]])?.first?.count, 48, "auf ganze Seiten gerundet")

        let back = try JSONDecoder().decode(SequencerPattern.self, from: data)
        XCTAssertEqual(back.steps[3].count, 64)
        XCTAssertTrue(back[3, 40].active)
        XCTAssertEqual(back[3, 40].velocity, 0.7, accuracy: 1e-9)
        XCTAssertEqual(back, p)
    }

    func testOldSixteenStepFilesStillLoad() throws {
        let row = Array(repeating: ["active": false], count: 16)
        let json: [String: Any] = ["name": "Alt", "length": 16, "steps": Array(repeating: row, count: 16), "gates": Array(repeating: 1, count: 16)]
        let p = try JSONDecoder().decode(SequencerPattern.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(p.steps.count, 16)
        XCTAssertTrue(p.steps.allSatisfy { $0.count == 64 })
        XCTAssertTrue(p.motion.isEmpty)
    }

    // MARK: Song-Modus

    func testSongModeFollowsChainAndLoops() {
        var a = SequencerPattern(name: "A", length: 4)
        a[0, 0] = SequencerStep(active: true)
        var b = SequencerPattern(name: "B", length: 4)
        b[1, 2] = SequencerStep(active: true)
        let e = engine(patterns: [a, b])
        e.send(.setSong(SongSnapshot(chain: [0, 1, 1])))
        e.send(.transport(.play))
        let found = onsets(renderEngine(e, frames: Int(stepFrames * 17)).left)
        // A@0, B@4+2, B@8+2, A@12 (Kette beginnt von vorn), B@16+2 liegt außerhalb
        let expected = [0, 6, 10, 12]
        XCTAssertEqual(found.count, expected.count)
        for (i, s) in expected.enumerated() {
            XCTAssertEqual(Double(found[i]), (Double(s) * stepFrames).rounded(.up), accuracy: 1, "Schritt \(s)")
        }
    }

    func testSongStatusReportsAudibleEntry() {
        let e = engine(patterns: [SequencerPattern(name: "A", length: 4), SequencerPattern(name: "B", length: 2)])
        e.send(.setSong(SongSnapshot(chain: [1, 0])))
        e.send(.transport(.play))
        _ = renderEngine(e, frames: Int(stepFrames * 1))
        XCTAssertEqual(e.status.currentPattern, 1)
        XCTAssertEqual(e.status.songIndex, 0)
        _ = renderEngine(e, frames: Int(stepFrames * 2.5))
        XCTAssertEqual(e.status.currentPattern, 0)
        XCTAssertEqual(e.status.songIndex, 1)
        e.send(.setSong(nil))
        _ = renderEngine(e, frames: 64)
        XCTAssertEqual(e.status.songIndex, -1)
    }

    func testAudiblePatternDoesNotSwitchEarly() {
        // Die Planung läuft einen Schritt voraus – angezeigt wird trotzdem das hörbare Pattern.
        let e = engine(patterns: [SequencerPattern(name: "A", length: 4), SequencerPattern(name: "B", length: 4)])
        e.send(.transport(.play))
        _ = renderEngine(e, frames: Int(stepFrames * 1))
        e.send(.selectPattern(slot: 1, immediately: false))
        _ = renderEngine(e, frames: Int(stepFrames * 2.5))
        XCTAssertEqual(e.status.currentPattern, 0)
        XCTAssertEqual(e.status.currentStep, 3)
        _ = renderEngine(e, frames: Int(stepFrames * 1))
        XCTAssertEqual(e.status.currentPattern, 1)
        XCTAssertEqual(e.status.currentStep, 0)
    }

    // MARK: Motion-Sequenz

    private func level(_ x: [Float], step: Double) -> Float {
        let c = Int(step * stepFrames)
        return TestAudio.rms(x[(c - 300)..<(c + 300)])
    }

    func testMotionHoldChangesParameterPerStep() {
        var p = SequencerPattern(name: "M", length: 4)
        p[0, 0] = SequencerStep(active: true, velocity: 1)
        p.recordMotion(parameter: .padVolume, pad: 0, step: 0, value: 1.0)
        p.recordMotion(parameter: .padVolume, pad: 0, step: 2, value: 0.25)
        let e = engine(patterns: [p], frames: Int(stepFrames * 5))
        e.send(.transport(.play))
        let out = renderEngine(e, frames: Int(stepFrames * 4)).left
        let l1 = level(out, step: 1.5), l3 = level(out, step: 3.5)
        XCTAssertEqual(l1, 0.5, accuracy: 0.02)
        XCTAssertEqual(l3 / l1, 0.25, accuracy: 0.02, "Schritt 2–3 halten den Wert von Schritt 2")
    }

    func testMotionSmoothInterpolates() {
        var p = SequencerPattern(name: "M", length: 4)
        p[0, 0] = SequencerStep(active: true, velocity: 1)
        p.recordMotion(parameter: .padVolume, pad: 0, step: 0, value: 1.0)
        p.recordMotion(parameter: .padVolume, pad: 0, step: 2, value: 0.0)
        let e = engine(patterns: [p], frames: Int(stepFrames * 5))
        e.send(.setMotionMode(.smooth))
        e.send(.transport(.play))
        let out = renderEngine(e, frames: Int(stepFrames * 4)).left
        XCTAssertEqual(level(out, step: 1.0) / 0.5, 0.5, accuracy: 0.05, "auf halbem Weg zwischen 1 und 0")
    }

    func testMotionOffAndStopRestoreBaseValue() {
        var p = SequencerPattern(name: "M", length: 4)
        p.recordMotion(parameter: .padVolume, pad: 0, step: 0, value: 0.1)
        let e = engine(patterns: [p], frames: 20_000)
        e.send(.transport(.play))
        _ = renderEngine(e, frames: 2_000)
        e.send(.transport(.stop))
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 3_000).left
        XCTAssertEqual(TestAudio.rms(out[1_000..<2_500]), 0.5, accuracy: 0.02, "nach Stopp gilt wieder der Grundwert")
    }

    func testMasterMotion() {
        var p = SequencerPattern(name: "M", length: 4)
        p[0, 0] = SequencerStep(active: true, velocity: 1)
        p.recordMotion(parameter: .masterVolume, pad: 0, step: 2, value: 0.5)
        p.recordMotion(parameter: .masterVolume, pad: 0, step: 0, value: 1.0)
        let e = engine(patterns: [p], frames: Int(stepFrames * 5))
        e.send(.transport(.play))
        let out = renderEngine(e, frames: Int(stepFrames * 4)).left
        let ratio = level(out, step: 3.5) / level(out, step: 1.5)
        // Master-Volume hat eine quadratische Kennlinie im Gain: Wert 0,5 → Gain 0,25
        XCTAssertLessThan(ratio, 0.6)
        XCTAssertGreaterThan(ratio, 0.1)
    }

    func testRecordMotionFillsGapsAndLimitsLanes() {
        var p = SequencerPattern(name: "M")
        p.recordMotion(parameter: .padCutoff, pad: 3, step: 2, value: 1000)
        p.recordMotion(parameter: .padCutoff, pad: 3, step: 6, value: 5000, fromStep: 2, fromValue: 1000)
        let lane = p.motion[0]
        XCTAssertEqual(lane.pad, 3)
        XCTAssertEqual(lane.values[4] ?? 0, 3000, accuracy: 1e-6)
        XCTAssertNil(lane.values[1])
        XCTAssertFalse(p.recordMotion(parameter: .tempo, pad: 0, step: 0, value: 100), "Tempo ist nicht aufzeichenbar")
        for i in 0..<40 {
            let id = ParameterID.allCases.filter(MotionLane.canRecord)[i % 47]
            p.recordMotion(parameter: id, pad: i / 47, step: 0, value: id.spec.defaultValue)
        }
        XCTAssertEqual(p.motion.count, MotionLane.maxLanes)
    }

    func testFillIsCyclic() {
        let (hold, smooth) = PatternSnapshot.fill([nil, 2, nil, 6])
        XCTAssertEqual(hold, [6, 2, 2, 6])
        XCTAssertEqual(smooth[2], 4, accuracy: 1e-9)
        XCTAssertEqual(smooth[0], 4, accuracy: 1e-9, "zwischen Schritt 3 (6) und Schritt 1 (2)")
    }

    func testMotionRoundTripsThroughJSON() throws {
        var doc = ProjectDocument(name: "M")
        doc.sequencer.patterns[0].recordMotion(parameter: .reverbMix, pad: 0, step: 5, value: 0.7)
        doc.sequencer.motionMode = .smooth
        doc.sequencer.songMode = true
        doc.patternChain = [0, 1, 1, 0]
        let back = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(back.sequencer.patterns[0].motion.first?.values[5] ?? nil, 0.7)
        XCTAssertEqual(back.sequencer.patterns[0].motion.first?.pad, -1)
        XCTAssertEqual(back.sequencer.motionMode, .smooth)
        XCTAssertTrue(back.sequencer.songMode)
        XCTAssertEqual(back.patternChain, [0, 1, 1, 0])
    }
}
