import XCTest
@testable import NexoraCore

final class DSPTests: XCTestCase {
    private let sr: Float = 44_100

    private func filtered(_ input: [Float], mode: FilterMode, cutoff: Float, resonance: Float = 0) -> [Float] {
        var f = StateVariableFilter()
        f.mode = mode
        f.setParameters(cutoff: cutoff, resonance: resonance, sampleRate: sr)
        return input.map { f.processMono($0) }
    }

    func testLowPassAttenuatesHighFrequencies() {
        let high = TestAudio.sine(frequency: 8_000, seconds: 0.5)
        let low = TestAudio.sine(frequency: 100, seconds: 0.5)
        let outHigh = filtered(high, mode: .lowPass, cutoff: 500)
        let outLow = filtered(low, mode: .lowPass, cutoff: 500)
        let attenuationHigh = DSP.gainToDb(TestAudio.rms(outHigh[4000...]) / TestAudio.rms(high))
        let attenuationLow = DSP.gainToDb(TestAudio.rms(outLow[4000...]) / TestAudio.rms(low))
        XCTAssertLessThan(attenuationHigh, -30)
        XCTAssertGreaterThan(attenuationLow, -1)
    }

    func testHighPassAttenuatesLowFrequencies() {
        let low = TestAudio.sine(frequency: 60, seconds: 0.5)
        let out = filtered(low, mode: .highPass, cutoff: 2_000)
        XCTAssertLessThan(DSP.gainToDb(TestAudio.rms(out[4000...]) / TestAudio.rms(low)), -40)
    }

    func testBandPassPassesCenterAndRejectsSides() {
        let center = TestAudio.sine(frequency: 1_000, seconds: 0.5)
        let side = TestAudio.sine(frequency: 10_000, seconds: 0.5)
        let c = TestAudio.rms(filtered(center, mode: .bandPass, cutoff: 1_000, resonance: 0.5)[4000...])
        let s = TestAudio.rms(filtered(side, mode: .bandPass, cutoff: 1_000, resonance: 0.5)[4000...])
        XCTAssertGreaterThan(c, s * 8)
    }

    func testFilterIsStableAtMaximumResonance() {
        var input = TestAudio.sine(frequency: 300, seconds: 1)
        input[0] = 1
        let out = filtered(input, mode: .lowPass, cutoff: 300, resonance: 1)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
        XCTAssertLessThan(out.map(abs).max()!, 100)
    }

    func testEQBoostAndCut() {
        var eq = ThreeBandEQ(sampleRate: 44_100)
        let x = TestAudio.sine(frequency: 1_000, seconds: 0.3)
        eq.configure(lowDb: 0, midDb: 12, highDb: 0, midFrequency: 1_000)
        let boosted = x.map { eq.process($0, $0).0 }
        XCTAssertEqual(DSP.gainToDb(TestAudio.rms(boosted[3000...]) / TestAudio.rms(x)), 12, accuracy: 1)
        var eq2 = ThreeBandEQ(sampleRate: 44_100)
        eq2.configure(lowDb: 0, midDb: 0, highDb: -12, midFrequency: 1_000)
        let hi = TestAudio.sine(frequency: 15_000, seconds: 0.3)
        let cut = hi.map { eq2.process($0, $0).0 }
        XCTAssertLessThan(DSP.gainToDb(TestAudio.rms(cut[3000...]) / TestAudio.rms(hi)), -9)
        var flat = ThreeBandEQ(sampleRate: 44_100)
        flat.configure(lowDb: 0, midDb: 0, highDb: 0, midFrequency: 1_000)
        XCTAssertTrue(flat.isFlat)
    }

    func testCompressorReducesLoudSignal() {
        var comp = Compressor(sampleRate: 44_100)
        comp.thresholdDb = -20
        comp.ratio = 8
        comp.attackSeconds = 0.001
        comp.updateTimes()
        let x = TestAudio.sine(frequency: 200, seconds: 0.5, amplitude: 0.9)
        let y = x.map { comp.process($0, $0).0 }
        let reduction = DSP.gainToDb(TestAudio.rms(y[10000...]) / TestAudio.rms(x[10000...]))
        XCTAssertLessThan(reduction, -10)
        XCTAssertLessThan(comp.currentGainReductionDb, -10)
        // Statische Kennlinie: unterhalb Threshold − Knee keine Reduktion.
        XCTAssertEqual(comp.gainReduction(forInputDb: -40), 0)
        XCTAssertEqual(comp.gainReduction(forInputDb: 0), (1.0 / 8 - 1) * 20, accuracy: 0.01)
    }

    func testBitcrusherQuantizesAndHolds() {
        var c = Bitcrusher()
        let (l, _) = c.process(0.3, 0.3, bits: 2, downsample: 1)
        // 2 Bit → Stufen von 0.5
        XCTAssertEqual(l, 0.5, accuracy: 0.0001)
        var hold = Bitcrusher()
        let values: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        let out = values.map { hold.process($0, $0, bits: 16, downsample: 3).0 }
        XCTAssertEqual(out, [0.1, 0.1, 0.1, 0.4, 0.4, 0.4], "Downsample 3 hält jeden Wert drei Samples")
        var bypass = Bitcrusher()
        XCTAssertEqual(bypass.process(0.123, -0.456, bits: 16, downsample: 1).0, 0.123)
    }

    func testDistortionIsBoundedAndNeutralAtZero() {
        XCTAssertEqual(Distortion.process(0.5, drive: 0), 0.5)
        for x in stride(from: Float(-4), through: 4, by: 0.25) {
            XCTAssertLessThanOrEqual(abs(Distortion.process(x, drive: 1)), 1.01)
        }
        let s = TestAudio.sine(frequency: 220, seconds: 0.2, amplitude: 0.3)
        let driven = s.map { Distortion.process($0, drive: 0.8) }
        XCTAssertGreaterThan(TestAudio.rms(driven), TestAudio.rms(s))
    }

    func testADSRStagesAndTiming() {
        var env = ADSREnvelope()
        let rate = 1_000.0
        env.configure(attack: 0.01, decay: 0.05, sustain: 0.5, release: 0.1, sampleRate: rate)
        env.noteOn()
        var values: [Float] = []
        for _ in 0..<10 { values.append(env.next()) }
        XCTAssertEqual(values.last!, 1, accuracy: 0.001, "Attack erreicht 1 nach 10 ms")
        for _ in 0..<200 { _ = env.next() }
        XCTAssertEqual(env.level, 0.5, accuracy: 0.001)
        XCTAssertEqual(env.stage, .sustain)
        env.noteOff()
        var count = 0
        while env.level > 0.5 * 0.001 && count < 10_000 { _ = env.next(); count += 1 }
        XCTAssertEqual(Double(count), 100, accuracy: 3, "Release erreicht −60 dB nach 100 ms")
        while env.isActive && count < 10_000 { _ = env.next(); count += 1 }
        XCTAssertFalse(env.isActive)
    }

    func testADSRMinimumAttackPreventsClick() {
        var env = ADSREnvelope()
        env.configure(attack: 0, decay: 1, sustain: 1, release: 0, sampleRate: 44_100)
        env.noteOn()
        XCTAssertLessThan(env.next(), 0.1, "Erstes Sample nicht sofort auf vollem Pegel")
    }

    func testLFORangeAndShapes() {
        for shape in LFOShape.allCases {
            var lfo = LFO()
            for _ in 0..<2000 {
                let v = lfo.next(shape: shape, rate: 5, sampleRate: 1000)
                XCTAssertGreaterThanOrEqual(v, -1.0001)
                XCTAssertLessThanOrEqual(v, 1.0001)
            }
        }
        var sine = LFO()
        XCTAssertEqual(sine.next(shape: .sine, rate: 1, sampleRate: 4), 0, accuracy: 0.0001)
        XCTAssertEqual(sine.next(shape: .sine, rate: 1, sampleRate: 4), 1, accuracy: 0.0001)
    }

    func testDelayProducesEchoAtConfiguredTime() {
        let rate = 44_100.0
        let delay = StereoDelay(sampleRate: rate)
        delay.delaySeconds = 0.1
        delay.feedback = 0
        delay.pingPong = false
        delay.damping = 0
        let n = 8_000
        var input = [Float](repeating: 0, count: n)
        input[0] = 1
        var outL = [Float](repeating: 0, count: n)
        var outR = [Float](repeating: 0, count: n)
        input.withUnsafeBufferPointer { inp in
            outL.withUnsafeMutableBufferPointer { ol in
                outR.withUnsafeMutableBufferPointer { orr in
                    delay.process(inL: inp.baseAddress!, inR: inp.baseAddress!, outL: ol.baseAddress!, outR: orr.baseAddress!, count: n)
                }
            }
        }
        let peakIndex = outL.indices.max(by: { abs(outL[$0]) < abs(outL[$1]) })!
        XCTAssertEqual(peakIndex, 4410, accuracy: 2)
    }

    func testReverbProducesDecayingTail() {
        let reverb = Reverb(sampleRate: 44_100)
        reverb.roomSize = 0.8
        let n = 44_100
        var input = [Float](repeating: 0, count: n)
        for i in 0..<100 { input[i] = 0.5 }
        var outL = [Float](repeating: 0, count: n)
        var outR = [Float](repeating: 0, count: n)
        input.withUnsafeBufferPointer { inp in
            outL.withUnsafeMutableBufferPointer { ol in
                outR.withUnsafeMutableBufferPointer { orr in
                    reverb.process(inL: inp.baseAddress!, inR: inp.baseAddress!, outL: ol.baseAddress!, outR: orr.baseAddress!, count: n)
                }
            }
        }
        let early = TestAudio.rms(outL[2_000..<10_000])
        let late = TestAudio.rms(outL[35_000..<44_000])
        XCTAssertGreaterThan(early, 0.001)
        XCTAssertLessThan(late, early)
        XCTAssertTrue(outL.allSatisfy { $0.isFinite })
        XCTAssertNotEqual(outL[5000], outR[5000], "Stereo-Hall erzeugt unterschiedliche Kanäle")
    }

    func testVectorOps() {
        var a: [Float] = [1, -3, 2]
        var b: [Float] = [1, 1, 1]
        a.withUnsafeMutableBufferPointer { ap in
            XCTAssertEqual(VectorOps.peak(ap.baseAddress!, count: 3), 3)
            b.withUnsafeMutableBufferPointer { bp in
                VectorOps.addScaled(ap.baseAddress!, scale: 2, into: bp.baseAddress!, count: 3)
            }
            VectorOps.clip(ap.baseAddress!, limit: 1.5, count: 3)
        }
        XCTAssertEqual(b, [3, -5, 5])
        XCTAssertEqual(a, [1, -1.5, 1.5])
    }

    func testHermiteInterpolationIsExactAtNodes() {
        XCTAssertEqual(DSP.hermite(0, 1, 2, 3, 0), 1)
        XCTAssertEqual(DSP.hermite(0, 1, 2, 3, 0.5), 1.5, accuracy: 0.0001)
    }
}
