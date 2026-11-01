import XCTest
@testable import NexoraCore

final class EngineTests: XCTestCase {
    private let sr = 44_100.0

    private func dcSample(_ value: Float = 0.5, frames: Int = 1000) -> SampleBuffer {
        SampleBuffer(name: "DC", sampleRate: sr, channels: [TestAudio.constant(value, frames: frames)])
    }

    private func rampSample(frames: Int = 4410) -> SampleBuffer {
        SampleBuffer(name: "Ramp", sampleRate: sr, channels: [(0..<frames).map { Float($0) / Float(frames) }])
    }

    private func engine(with sample: SampleBuffer, settings: PadSettings = neutralPadSettings(), pad: Int = 0) -> SamplerEngine {
        let e = makeNeutralEngine()
        e.send(.setSample(pad: pad, sample: sample))
        e.send(.setPadSettings(pad: pad, settings: settings))
        return e
    }

    private func lastNonZero(_ x: [Float], threshold: Float = 1e-5) -> Int {
        x.lastIndex(where: { abs($0) > threshold }) ?? -1
    }

    func testNoteOnPlaysSample() {
        let e = engine(with: dcSample())
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 2000)
        XCTAssertEqual(out.left[500], 0.5, accuracy: 0.01)
        XCTAssertEqual(out.right[500], 0.5, accuracy: 0.01)
        XCTAssertEqual(e.status.padTriggerCount(0), 1)
    }

    func testOneShotStopsAtSampleEnd() {
        let e = engine(with: dcSample(frames: 1000))
        e.send(.noteOn(pad: 0, velocity: 1))
        e.send(.noteOff(pad: 0)) // wird im One-Shot-Modus ignoriert
        let out = renderEngine(e, frames: 3000)
        XCTAssertEqual(out.left[900], 0.5, accuracy: 0.01)
        XCTAssertEqual(Double(lastNonZero(out.left)), 1000, accuracy: 3)
        XCTAssertEqual(e.status.activeVoices, 0)
    }

    func testStartAndStopAreClickFree() {
        let e = engine(with: dcSample(0.9, frames: 2000))
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 3000).left
        var maxStep: Float = 0
        for i in 1..<out.count { maxStep = max(maxStep, abs(out[i] - out[i - 1])) }
        XCTAssertLessThan(maxStep, 0.06, "Keine sprunghaften Pegeländerungen am Anfang/Ende")
    }

    func testPitchUpOctaveHalvesDuration() {
        var s = neutralPadSettings()
        s.pitch = 12
        let e = engine(with: dcSample(frames: 2000), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 4000)
        XCTAssertEqual(Double(lastNonZero(out.left)), 1000, accuracy: 4)
    }

    func testSpeedChangesDuration() {
        var s = neutralPadSettings()
        s.speed = 0.5
        let e = engine(with: dcSample(frames: 1000), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        XCTAssertEqual(Double(lastNonZero(renderEngine(e, frames: 4000).left)), 2000, accuracy: 4)
    }

    func testTimeStretchKeepsDurationWhenPitching() {
        var s = neutralPadSettings()
        s.pitchMode = .timeStretch
        s.pitch = 12
        let frames = 44_100
        let e = engine(with: SampleBuffer(name: "Sine", sampleRate: sr, channels: [TestAudio.sine(frequency: 220, seconds: 1)]), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: frames * 2).left
        let duration = Double(lastNonZero(out)) / sr
        XCTAssertEqual(duration, 1.0, accuracy: 0.08, "Time-Stretch: Dauer bleibt trotz Pitch erhalten")
        // Tonhöhe verdoppelt: Nulldurchgänge im stationären Teil zählen.
        let segment = Array(out[11_025..<33_075])
        var crossings = 0
        for i in 1..<segment.count where (segment[i - 1] < 0) != (segment[i] < 0) { crossings += 1 }
        let frequency = Double(crossings) / 2 / 0.5
        XCTAssertEqual(frequency, 440, accuracy: 25)
    }

    func testReversePlaysBackwards() {
        var s = neutralPadSettings()
        s.reverse = true
        let e = engine(with: rampSample(), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 200).left
        XCTAssertGreaterThan(out[100], 0.9)
        let forward = engine(with: rampSample())
        forward.send(.noteOn(pad: 0, velocity: 1))
        XCTAssertLessThan(renderEngine(forward, frames: 200).left[100], 0.1)
    }

    func testSampleStartAndEndRegion() {
        var s = neutralPadSettings()
        s.start = 0.5
        s.end = 0.75
        let e = engine(with: rampSample(frames: 4000), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 3000).left
        XCTAssertEqual(out[100], 0.525, accuracy: 0.02)
        XCTAssertEqual(Double(lastNonZero(out)), 1000, accuracy: 4)
    }

    func testLoopModeSustainsUntilNoteOffThenReleases() {
        var s = neutralPadSettings()
        s.playMode = .loop
        s.release = 0.02
        let e = engine(with: dcSample(frames: 500), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let held = renderEngine(e, frames: 5000).left
        XCTAssertEqual(held[4500], 0.5, accuracy: 0.01, "Loop läuft über das Sample-Ende hinaus")
        e.send(.noteOff(pad: 0))
        let released = renderEngine(e, frames: 5000).left
        XCTAssertEqual(released[4000], 0, accuracy: 0.0001)
    }

    func testGateModeReleasesOnNoteOff() {
        var s = neutralPadSettings()
        s.playMode = .gate
        s.release = 0.01
        let e = engine(with: dcSample(frames: 44_100), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        _ = renderEngine(e, frames: 1000)
        e.send(.noteOff(pad: 0))
        let out = renderEngine(e, frames: 3000).left
        XCTAssertEqual(out[2500], 0, accuracy: 0.0001)
    }

    func testVolumePanAndVelocity() {
        var s = neutralPadSettings()
        s.volume = 0.5
        s.pan = -1
        let e = engine(with: dcSample(), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 600)
        XCTAssertEqual(out.left[500], 0.25, accuracy: 0.01)
        XCTAssertEqual(out.right[500], 0, accuracy: 0.0001)

        var v = neutralPadSettings()
        v.velocitySensitivity = 1
        let e2 = engine(with: dcSample(), settings: v)
        e2.send(.noteOn(pad: 0, velocity: 0.5))
        XCTAssertEqual(renderEngine(e2, frames: 600).left[500], 0.125, accuracy: 0.01)
    }

    func testPolyphonyLimitWithVoiceStealing() {
        let e = engine(with: dcSample(0.1, frames: 44_100))
        e.send(.setEngineSettings(EngineSettings(polyphony: 4, stealMode: .oldest)))
        for _ in 0..<10 { e.send(.noteOn(pad: 0, velocity: 1)) }
        let out = renderEngine(e, frames: 2048)
        XCTAssertLessThanOrEqual(e.status.activeVoices, 4)
        XCTAssertEqual(out.left[2000], 0.4, accuracy: 0.02, "Genau vier Stimmen klingen")
    }

    func testStealModeNoneRejectsNewNotes() {
        let e = makeNeutralEngine()
        for pad in 0..<3 {
            e.send(.setSample(pad: pad, sample: dcSample(0.1, frames: 44_100)))
            e.send(.setPadSettings(pad: pad, settings: neutralPadSettings()))
        }
        e.send(.setEngineSettings(EngineSettings(polyphony: 2, stealMode: .none)))
        for pad in 0..<3 { e.send(.noteOn(pad: pad, velocity: 1)) }
        _ = renderEngine(e, frames: 512)
        XCTAssertEqual(e.status.padTriggerCount(2), 0)
        XCTAssertEqual(e.status.activeVoices, 2)
    }

    func testSamePadStealingPrefersSamePad() {
        let e = makeNeutralEngine()
        for pad in 0..<2 {
            e.send(.setSample(pad: pad, sample: dcSample(0.1, frames: 44_100)))
            e.send(.setPadSettings(pad: pad, settings: neutralPadSettings()))
        }
        e.send(.setEngineSettings(EngineSettings(polyphony: 2, stealMode: .samePad)))
        e.send(.noteOn(pad: 0, velocity: 1))
        e.send(.noteOn(pad: 1, velocity: 1))
        _ = renderEngine(e, frames: 512)
        e.send(.noteOn(pad: 1, velocity: 1))
        _ = renderEngine(e, frames: 2048)
        XCTAssertGreaterThan(e.status.padLevel(0), 0.5, "Pad 1 (älteste Stimme) bleibt erhalten")
    }

    func testChokeGroupCutsOtherPad() {
        var s = neutralPadSettings()
        s.chokeGroup = 1
        let e = makeNeutralEngine()
        for pad in [4, 5] {
            e.send(.setSample(pad: pad, sample: dcSample(0.3, frames: 44_100)))
            e.send(.setPadSettings(pad: pad, settings: s))
        }
        e.send(.noteOn(pad: 4, velocity: 1))
        _ = renderEngine(e, frames: 1000)
        e.send(.noteOn(pad: 5, velocity: 1))
        let out = renderEngine(e, frames: 1000)
        XCTAssertEqual(out.left[900], 0.3, accuracy: 0.01, "Nur noch Pad 6 klingt")
    }

    func testPadFilterAttenuates() {
        let sine = SampleBuffer(name: "S", sampleRate: sr, channels: [TestAudio.sine(frequency: 6_000, seconds: 0.5)])
        let dry = engine(with: sine)
        dry.send(.noteOn(pad: 0, velocity: 1))
        let dryRMS = TestAudio.rms(renderEngine(dry, frames: 10_000).left[2000...])
        var s = neutralPadSettings()
        s.filterMode = .lowPass
        s.cutoff = 300
        let wet = engine(with: sine, settings: s)
        wet.send(.noteOn(pad: 0, velocity: 1))
        let wetRMS = TestAudio.rms(renderEngine(wet, frames: 10_000).left[2000...])
        XCTAssertLessThan(wetRMS, dryRMS * 0.05)
    }

    func testPadLFOTremoloModulatesLevel() {
        var s = neutralPadSettings()
        s.lfoTarget = .volume
        s.lfoDepth = 1
        s.lfoRate = 10
        let e = engine(with: dcSample(0.5, frames: 44_100), settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 20_000).left[1000...]
        XCTAssertLessThan(out.min()!, 0.05)
        XCTAssertGreaterThan(out.max()!, 0.45)
    }

    func testPadDriveAndCrushChangeSignal() {
        let sine = SampleBuffer(name: "S", sampleRate: sr, channels: [TestAudio.sine(frequency: 200, seconds: 0.3, amplitude: 0.4)])
        var s = neutralPadSettings()
        s.crushBits = 3
        let e = engine(with: sine, settings: s)
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 8000).left[2000..<6000]
        XCTAssertLessThanOrEqual(Set(out.map { ($0 * 1000).rounded() }).count, 12)
    }

    func testMasterFilterDelayReverbAndCrusherAffectSignal() {
        let click = SampleBuffer(name: "C", sampleRate: sr, channels: [TestAudio.constant(0.5, frames: 200)])
        func run(_ configure: (inout MasterSettings) -> Void) -> [Float] {
            let e = engine(with: click, settings: {
                var s = neutralPadSettings(); s.reverbSend = 1; s.delaySend = 1; return s
            }())
            var m = MasterSettings()
            m.volume = 1
            configure(&m)
            e.send(.setMaster(m))
            e.send(.noteOn(pad: 0, velocity: 1))
            return renderEngine(e, frames: 20_000).left
        }
        let dry = run { _ in }
        XCTAssertEqual(TestAudio.rms(dry[1000...]), 0, accuracy: 1e-6)
        let reverb = run { $0.reverbMix = 1 }
        XCTAssertGreaterThan(TestAudio.rms(reverb[1000...]), 0.001, "Hall erzeugt eine Fahne")
        let delay = run { $0.delayMix = 1; $0.delaySync = .off; $0.delayTime = 0.1; $0.delayFeedback = 0 }
        XCTAssertGreaterThan(abs(delay[4410 + 100]), 0.2, "Echo nach 100 ms")
        let crushed = run { $0.crushBits = 2 }
        XCTAssertEqual(crushed[100], 0.5, accuracy: 0.001)
    }

    func testMasterModulationTremolo() {
        let e = engine(with: dcSample(0.5, frames: 44_100))
        var m = MasterSettings()
        m.volume = 1
        m.modTarget = .tremolo
        m.modDepth = 1
        m.modRate = 8
        e.send(.setMaster(m))
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 20_000).left[1000...]
        XCTAssertLessThan(out.min()!, 0.05)
    }

    func testMasterLowPassFilterSweep() {
        let sine = SampleBuffer(name: "S", sampleRate: sr, channels: [TestAudio.sine(frequency: 5_000, seconds: 1)])
        let e = engine(with: sine)
        var m = MasterSettings()
        m.volume = 1
        m.filterMode = .lowPass
        m.filterCutoff = 200
        e.send(.setMaster(m))
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 20_000).left
        XCTAssertLessThan(TestAudio.rms(out[10_000...]), 0.01)
    }

    func testOutputNeverExceedsFullScale() {
        let e = makeNeutralEngine()
        e.send(.setSample(pad: 0, sample: dcSample(1, frames: 44_100)))
        var s = neutralPadSettings()
        s.volume = 1.25
        e.send(.setPadSettings(pad: 0, settings: s))
        for _ in 0..<16 { e.send(.noteOn(pad: 0, velocity: 1)) }
        let out = renderEngine(e, frames: 4000)
        XCTAssertLessThanOrEqual(out.left.map(abs).max()!, 1)
    }

    func testPreviewBypassesEffectsAndPads() {
        let e = makeNeutralEngine()
        e.send(.preview(sample: dcSample(0.4, frames: 2000), gain: 1))
        let out = renderEngine(e, frames: 1000)
        XCTAssertEqual(out.left[800], 0.4, accuracy: 0.01)
        e.send(.preview(sample: nil, gain: 1))
        let stopped = renderEngine(e, frames: 2000)
        XCTAssertEqual(stopped.left[1500], 0, accuracy: 0.0001)
    }

    func testReplacingSampleWhilePlayingIsSafe() {
        let e = engine(with: dcSample(0.5, frames: 20_000))
        e.send(.noteOn(pad: 0, velocity: 1))
        _ = renderEngine(e, frames: 1000)
        e.send(.setSample(pad: 0, sample: dcSample(0.2, frames: 20_000)))
        e.send(.noteOn(pad: 0, velocity: 1))
        let out = renderEngine(e, frames: 30_000)
        e.drainGarbage()
        XCTAssertEqual(out.left[500], 0.7, accuracy: 0.02, "Alte und neue Stimme überlagern sich")
        XCTAssertEqual(out.left[19_500], 0.2, accuracy: 0.02, "Nur noch die neue Stimme")
    }

    func testSampleRateConversionOnPlayback() {
        // 22,05-kHz-Sample spielt in einer 44,1-kHz-Engine mit korrekter Dauer.
        let sample = SampleBuffer(name: "Low", sampleRate: 22_050, channels: [TestAudio.constant(0.5, frames: 1000)])
        let e = engine(with: sample)
        e.send(.noteOn(pad: 0, velocity: 1))
        XCTAssertEqual(Double(lastNonZero(renderEngine(e, frames: 4000).left)), 2000, accuracy: 4)
    }
}
