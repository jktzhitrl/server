import Foundation
import Dispatch

/// Die Audio-Engine des NEXORA Samplers.
///
/// - Rendert 16 Pads mit eigener Sample-Wiedergabe, Hüllkurve, Filter, LFO, Drive und
///   Bitcrusher, eine Master-Effektkette sowie den integrierten Step-Sequencer.
/// - Echtzeitsicher: keine Allokationen, keine blockierenden Locks im Audio-Thread.
/// - Wird identisch für die Live-Wiedergabe (AVAudioSourceNode) und den Offline-Export
///   verwendet; der Export enthält daher exakt das hörbare Signal.
public final class SamplerEngine: @unchecked Sendable {
    public static let padCount = 16
    public static let physicalVoiceCount = EngineSettings.maximumPolyphony + 16
    static let maxChunk = 512

    public let sampleRate: Double
    public let status = EngineStatus()

    // Stimmen
    private let voices: UnsafeMutablePointer<Voice>
    private var previewVoice = Voice()
    private var voiceCounter: UInt64 = 0

    // Pad-Zustand (nur im Audio-Thread verändert)
    private let padSettings: UnsafeMutablePointer<PadSettings>
    private let padSamples: UnsafeMutablePointer<SampleBuffer?>
    private let padLevels: UnsafeMutablePointer<Float>
    private let padTriggers: UnsafeMutablePointer<Float>
    private let lastManualHit: UnsafeMutablePointer<Double>
    private var previewSettings = PadSettings()
    private var previewGain: Float = 1

    private var master = MasterSettings()
    private var engineSettings = EngineSettings()
    private var isRecording = false

    // Busse
    private let dryL: UnsafeMutablePointer<Float>, dryR: UnsafeMutablePointer<Float>
    private let revL: UnsafeMutablePointer<Float>, revR: UnsafeMutablePointer<Float>
    private let dlyL: UnsafeMutablePointer<Float>, dlyR: UnsafeMutablePointer<Float>
    private let wetRevL: UnsafeMutablePointer<Float>, wetRevR: UnsafeMutablePointer<Float>
    private let wetDlyL: UnsafeMutablePointer<Float>, wetDlyR: UnsafeMutablePointer<Float>
    private let postL: UnsafeMutablePointer<Float>, postR: UnsafeMutablePointer<Float>
    private let allBuffers: [UnsafeMutablePointer<Float>]

    // Master-Effekte
    private let delay: StereoDelay
    private let reverb: Reverb
    private let vibrato: VibratoProcessor
    private var masterFilter = StateVariableFilter()
    private var masterCrusher = Bitcrusher()
    private var eq: ThreeBandEQ
    private var compressor: Compressor
    private var modLFO = LFO()
    private var masterVolume: SmoothedValue
    private var filterWet: SmoothedValue
    private var cutoffLog: SmoothedValue
    private var delayMixSmooth: SmoothedValue
    private var reverbMixSmooth: SmoothedValue
    private var lastFilterMode: FilterMode = .lowPass
    /// Vor dem ersten gerenderten Block springen geglättete Werte direkt auf ihr Ziel,
    /// damit Wiedergabe und Export ohne Einschwingen beginnen.
    private var primed = false

    // Metronom
    private var clickRemaining = 0
    private var clickPhase: Float = 0
    private var clickFrequency: Float = 1000
    private var clickLength = 1

    // Sequencer & Warteschlangen
    let sequencer = SequencerClock()
    private let commands = RealtimeRing<EngineCommand>(capacity: 4096)
    private let garbage = RealtimeRing<AnyObject>(capacity: 1024)
    private let events = RealtimeRing<EngineEvent>(capacity: 512)

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let vc = Self.physicalVoiceCount
        voices = .allocate(capacity: vc)
        voices.initialize(repeating: Voice(), count: vc)
        padSettings = .allocate(capacity: Self.padCount)
        padSettings.initialize(repeating: PadSettings(), count: Self.padCount)
        padSamples = .allocate(capacity: Self.padCount)
        padSamples.initialize(repeating: nil, count: Self.padCount)
        padLevels = .allocate(capacity: Self.padCount + 1)
        padLevels.initialize(repeating: 0, count: Self.padCount + 1)
        padTriggers = .allocate(capacity: Self.padCount)
        padTriggers.initialize(repeating: 0, count: Self.padCount)
        lastManualHit = .allocate(capacity: Self.padCount)
        lastManualHit.initialize(repeating: -1000, count: Self.padCount)

        func buffer() -> UnsafeMutablePointer<Float> {
            let b = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxChunk)
            b.initialize(repeating: 0, count: Self.maxChunk)
            return b
        }
        dryL = buffer(); dryR = buffer(); revL = buffer(); revR = buffer()
        dlyL = buffer(); dlyR = buffer(); wetRevL = buffer(); wetRevR = buffer()
        wetDlyL = buffer(); wetDlyR = buffer(); postL = buffer(); postR = buffer()
        allBuffers = [dryL, dryR, revL, revR, dlyL, dlyR, wetRevL, wetRevR, wetDlyL, wetDlyR, postL, postR]

        delay = StereoDelay(sampleRate: sampleRate)
        reverb = Reverb(sampleRate: sampleRate)
        vibrato = VibratoProcessor(sampleRate: sampleRate)
        eq = ThreeBandEQ(sampleRate: sampleRate)
        compressor = Compressor(sampleRate: sampleRate)
        masterVolume = SmoothedValue(value: 0.64, timeSeconds: 0.02, sampleRate: sampleRate)
        filterWet = SmoothedValue(value: 0, timeSeconds: 0.01, sampleRate: sampleRate)
        cutoffLog = SmoothedValue(value: log2f(20_000), timeSeconds: 0.03, sampleRate: sampleRate / 16)
        delayMixSmooth = SmoothedValue(value: 0, timeSeconds: 0.02, sampleRate: sampleRate)
        reverbMixSmooth = SmoothedValue(value: 0, timeSeconds: 0.02, sampleRate: sampleRate)

        previewSettings.volume = 1
        previewSettings.reverbSend = 0
        previewSettings.delaySend = 0
        previewSettings.velocitySensitivity = 0
        previewSettings.release = 0.01
        applyMaster(master)
    }

    deinit {
        voices.deinitialize(count: Self.physicalVoiceCount)
        voices.deallocate()
        padSettings.deinitialize(count: Self.padCount)
        padSettings.deallocate()
        padSamples.deinitialize(count: Self.padCount)
        padSamples.deallocate()
        padLevels.deallocate()
        padTriggers.deallocate()
        lastManualHit.deallocate()
        allBuffers.forEach { $0.deallocate() }
    }

    // MARK: - Öffentliche Schnittstelle (beliebiger Thread)

    /// Reiht einen Befehl ein. Thread-sicher; der Befehl wird im nächsten Audio-Block ausgeführt.
    @discardableResult
    public func send(_ command: EngineCommand) -> Bool {
        commands.push(command)
    }

    /// Gibt im Audio-Thread ersetzte Objekte (Samples, Patterns) frei.
    /// Regelmäßig vom Haupt-Thread aufrufen.
    public func drainGarbage() {
        garbage.drain { _ in }
    }

    /// Liefert Rückmeldungen der Engine (Aufnahme, Pattern-Wechsel). Vom Haupt-Thread aufrufen.
    public func pollEvents(_ body: (EngineEvent) -> Void) {
        events.drain(body)
    }

    /// Position des Sequencers in Schritten. Nur im Offline-Betrieb (gleicher Thread) verwenden.
    public var sequencerPosition: Double { sequencer.position }
    public var sequencerSlot: Int { sequencer.currentSlot }

    // MARK: - Rendering

    /// Rendert `frameCount` Stereo-Frames. Aufruf aus dem Audio-Thread bzw. beim Export.
    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = commands.tryDrain { handle($0) }
        var done = 0
        while done < frameCount {
            let n = min(Self.maxChunk, frameCount - done)
            renderChunk(count: n, outL: left + done, outR: right + done)
            done += n
        }
        publishStatus(frames: frameCount, startTime: start, outL: left, outR: right)
    }

    private func renderChunk(count n: Int, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>) {
        for b in allBuffers { VectorOps.clear(b, count: n) }
        var t = 0
        while t < n {
            var chunk = n - t
            let sps = sequencer.stepsPerSample(sampleRate: sampleRate)
            if sequencer.state == .playing {
                sequencer.schedule(until: sequencer.position + 1.0, isRecording: isRecording)
                while let e = sequencer.popDueEvent(at: sequencer.position) { handleSequencerEvent(e) }
                if let next = sequencer.nextEventTime() {
                    let frames = Int(((next - sequencer.position) / sps).rounded(.up))
                    chunk = min(chunk, max(1, frames))
                }
                chunk = min(chunk, max(1, Int(0.5 / sps)))
            } else {
                // Auch ohne Wiedergabe müssen fällige Note-Offs (nach Stop) verarbeitet werden.
                while let e = sequencer.popDueEvent(at: .infinity) {
                    if e.kind == .noteOff { handleSequencerEvent(e) }
                }
            }
            renderVoices(offset: t, count: chunk)
            renderClick(offset: t, count: chunk)
            sequencer.advance(by: Double(chunk) * sps)
            t += chunk
        }
        processMaster(count: n, outL: outL, outR: outR)
    }

    private func renderVoices(offset: Int, count: Int) {
        for v in 0..<Self.physicalVoiceCount where voices[v].active {
            renderVoice(voices + v, offset: offset, count: count,
                        dry: (dryL, dryR), reverb: (revL, revR), delay: (dlyL, dlyR))
        }
        if previewVoice.active {
            withUnsafeMutablePointer(to: &previewVoice) { p in
                renderVoice(p, offset: offset, count: count,
                            dry: (postL, postR), reverb: nil, delay: nil)
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func renderVoice(_ vp: UnsafeMutablePointer<Voice>, offset: Int, count: Int,
                             dry: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>),
                             reverb: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>)?,
                             delay: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>)?) {
        var v = vp.pointee
        guard let sample = v.sample else {
            vp.pointee.active = false
            return
        }
        let s = v.isPreview ? previewSettings : padSettings[v.pad]
        let sr = sampleRate
        let frames = Double(sample.frameCount)
        let regionStart = DSP.clamp(s.start, 0, 1) * frames
        var regionEnd = DSP.clamp(s.end, 0, 1) * frames
        if regionEnd < regionStart + 2 { regionEnd = min(frames, regionStart + 2) }
        let regionLength = max(regionEnd - regionStart, 1)
        let direction: Double = s.reverse ? -1 : 1
        let looping = s.playMode == .loop && !v.isPreview
        let stretch = s.pitchMode == .timeStretch && !v.isPreview
        let srRatio = sample.sampleRate / sr
        let baseSemitones = s.pitch + s.fineTune / 100 + v.transpose
        let speed = DSP.clamp(s.speed, 0.25, 4)

        var pitchRatio = DSP.semitonesToRatio(baseSemitones)
        var rate = srRatio * pitchRatio * speed
        var grainTranspose = srRatio * pitchRatio
        let headRate = srRatio * speed
        let grainLength = 0.05 * sr
        let grainIncrement = 1 / grainLength

        let lfoDepth = Float(DSP.clamp(s.lfoDepth, 0, 1))
        let lfoActive = s.lfoTarget != .off && lfoDepth > 0.0001
        let baseCutoff = Float(s.cutoff)
        let resonance = Float(s.resonance)
        let envAmount = Float(DSP.clamp(s.filterEnvAmount, -1, 1))
        let filterEnvActive = s.filterMode != .off && abs(envAmount) > 0.0001
        var lfoCutoffOctaves: Float = 0
        v.filter.mode = s.filterMode
        if s.filterMode != .off {
            v.filter.setParameters(cutoff: baseCutoff, resonance: resonance, sampleRate: Float(sr))
        }
        v.envelope.configure(attack: s.attack, decay: s.decay, sustain: s.sustain, release: s.release, sampleRate: sr)
        v.gain.target = Float(s.volume) * v.velocityGain * (v.isPreview ? previewGain : 1)

        var (panL, panR) = DSP.balanceGains(Float(s.pan))
        var tremolo: Float = 1
        let revSend = Float(s.reverbSend)
        let dlySend = Float(s.delaySend)
        let drive: Float = s.insertFXOn ? Float(s.drive) : 0
        let bits: Float = s.insertFXOn ? Float(s.crushBits) : 16
        let downsample: Float = s.insertFXOn ? Float(s.crushDownsample) : 1
        let crushActive = bits < 15.99 || downsample > 1.001
        let filterActive = s.filterMode != .off
        let endFadeFrames = 48.0

        let outDryL = dry.0 + offset, outDryR = dry.1 + offset
        var finished = false
        var peak: Float = 0

        @inline(__always) func wrap(_ p: Double) -> Double {
            var x = p
            if x >= regionEnd { x = regionStart + (x - regionEnd).truncatingRemainder(dividingBy: regionLength) }
            if x < regionStart { x = regionEnd - (regionStart - x).truncatingRemainder(dividingBy: regionLength) }
            return x
        }

        for i in 0..<count {
            if lfoActive && (i & 15) == 0 {
                let raw = v.lfo.next(shape: s.lfoShape, rate: s.lfoRate, sampleRate: sr, samples: 16)
                switch s.lfoTarget {
                case .pitch:
                    pitchRatio = DSP.semitonesToRatio(baseSemitones + Double(raw * lfoDepth) * 2)
                    rate = srRatio * pitchRatio * speed
                    grainTranspose = srRatio * pitchRatio
                case .volume:
                    tremolo = 1 - lfoDepth * (0.5 + 0.5 * raw)
                case .cutoff:
                    lfoCutoffOctaves = raw * lfoDepth * 3
                    if filterActive && !filterEnvActive {
                        let c = baseCutoff * exp2f(lfoCutoffOctaves)
                        v.filter.setParameters(cutoff: c, resonance: resonance, sampleRate: Float(sr))
                    }
                case .pan:
                    (panL, panR) = DSP.balanceGains(Float(s.pan) + raw * lfoDepth)
                case .off:
                    break
                }
            }

            if filterEnvActive && (i & 15) == 0 {
                let octaves = lfoCutoffOctaves + envAmount * v.envelope.level * 6
                v.filter.setParameters(cutoff: min(baseCutoff * exp2f(octaves), 20_000), resonance: resonance, sampleRate: Float(sr))
            }

            var l: Float = 0, r: Float = 0
            var remaining: Double
            if stretch {
                // Granulares Time-Stretching: zwei überlappende Hann-Grains.
                let span = grainLength * grainTranspose * direction
                let w0: Float
                if v.firstGrain && v.grain0Phase < 0.5 {
                    w0 = 1
                } else {
                    let sn = sinf(Float.pi * Float(v.grain0Phase))
                    w0 = sn * sn
                }
                var p0 = v.grain0Start + v.grain0Phase * span
                if looping { p0 = wrap(p0) }
                if p0 >= regionStart && p0 < regionEnd {
                    let (a, b) = sample.read(at: p0)
                    l += a * w0; r += b * w0
                }
                if v.grain1Phase >= 0 {
                    let sn = sinf(Float.pi * Float(v.grain1Phase))
                    let w1 = sn * sn
                    var p1 = v.grain1Start + v.grain1Phase * span
                    if looping { p1 = wrap(p1) }
                    if p1 >= regionStart && p1 < regionEnd {
                        let (a, b) = sample.read(at: p1)
                        l += a * w1; r += b * w1
                    }
                }
                v.grain0Phase += grainIncrement
                if v.grain0Phase >= 1 {
                    v.grain0Phase -= 1
                    v.grain0Start = v.readHead
                    v.firstGrain = false
                }
                let previous1 = v.grain1Phase
                v.grain1Phase += grainIncrement
                if v.grain1Phase >= 1 {
                    v.grain1Phase -= 1
                    v.grain1Start = v.readHead
                } else if previous1 < 0 && v.grain1Phase >= 0 {
                    v.grain1Start = v.readHead
                }
                v.readHead += headRate * direction
                if direction > 0 && v.readHead >= regionEnd {
                    if looping { v.readHead = wrap(v.readHead) } else { finished = true }
                } else if direction < 0 && v.readHead < regionStart {
                    if looping { v.readHead = wrap(v.readHead) } else { finished = true }
                }
                remaining = (direction > 0 ? regionEnd - v.readHead : v.readHead - regionStart) / headRate
            } else {
                (l, r) = sample.read(at: v.position)
                v.position += rate * direction
                if direction > 0 && v.position >= regionEnd {
                    if looping { v.position = wrap(v.position) } else { finished = true }
                } else if direction < 0 && v.position < regionStart {
                    if looping { v.position = wrap(v.position) } else { finished = true }
                }
                remaining = (direction > 0 ? regionEnd - v.position : v.position - regionStart) / rate
            }

            let env = v.envelope.next()
            var fade: Float = 1
            if !looping && remaining < endFadeFrames {
                fade = Float(max(0, remaining) / endFadeFrames)
            }
            if v.fadeStep > 0 {
                v.fadeGain -= v.fadeStep
                if v.fadeGain <= 0 { v.fadeGain = 0; finished = true }
            }

            if filterActive { (l, r) = v.filter.process(l, r) }
            if drive > 0.0001 {
                l = Distortion.process(l, drive: drive)
                r = Distortion.process(r, drive: drive)
            }
            if crushActive { (l, r) = v.crusher.process(l, r, bits: bits, downsample: downsample) }

            let g = v.gain.next() * env * fade * v.fadeGain * tremolo
            let oL = l * g * panL
            let oR = r * g * panR
            outDryL[i] += oL
            outDryR[i] += oR
            if let reverb {
                reverb.0[offset + i] += oL * revSend
                reverb.1[offset + i] += oR * revSend
            }
            if let delay {
                delay.0[offset + i] += oL * dlySend
                delay.1[offset + i] += oR * dlySend
            }
            let lv = env * v.fadeGain * v.velocityGain
            if lv > peak { peak = lv }

            if finished || !v.envelope.isActive {
                finished = true
                break
            }
        }

        v.level = peak
        let levelIndex = v.isPreview ? Self.padCount : v.pad
        if peak > padLevels[levelIndex] { padLevels[levelIndex] = peak }

        if finished {
            releaseVoiceSample(&v)
            v.active = false
            v.level = 0
        }
        vp.pointee = v
    }

    /// Gibt die Sample-Referenz einer beendeten Stimme ab, ohne im Audio-Thread Speicher freizugeben.
    @inline(__always)
    private func releaseVoiceSample(_ v: inout Voice) {
        if let s = v.sample {
            let stillOwned = !v.isPreview && padSamples[v.pad] === s
            if !stillOwned { _ = garbage.tryPush(s) }
        }
        v.sample = nil
    }

    private func renderClick(offset: Int, count: Int) {
        guard clickRemaining > 0 else { return }
        let inc = 2 * Float.pi * clickFrequency / Float(sampleRate)
        for i in 0..<count where clickRemaining > 0 {
            let env = Float(clickRemaining) / Float(clickLength)
            let s = sinf(clickPhase) * env * env * 0.35
            clickPhase += inc
            if clickPhase > 2 * Float.pi { clickPhase -= 2 * Float.pi }
            postL[offset + i] += s
            postR[offset + i] += s
            clickRemaining -= 1
        }
    }

    // swiftlint:disable:next function_body_length
    private func processMaster(count n: Int, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>) {
        delay.delaySeconds = master.effectiveDelaySeconds(bpm: sequencer.bpm)
        delay.process(inL: dlyL, inR: dlyR, outL: wetDlyL, outR: wetDlyR, count: n)
        reverb.process(inL: revL, inR: revR, outL: wetRevL, outR: wetRevR, count: n)

        delayMixSmooth.target = Float(master.delayMix)
        reverbMixSmooth.target = Float(master.reverbMix)
        masterVolume.target = Float(master.volume * master.volume)

        // Filter-Bypass: LP ganz offen, HP ganz zu oder OFF → Filter wird weich ausgeblendet.
        let mode = master.filterMode
        let bypass = mode == .off
            || (mode == .lowPass && master.filterCutoff >= 19_500)
            || (mode == .highPass && master.filterCutoff <= 21)
        filterWet.target = bypass ? 0 : 1
        if mode != .off && mode != lastFilterMode {
            masterFilter.reset()
        }
        if mode != .off { masterFilter.mode = mode; lastFilterMode = mode }
        if mode == .off && filterWet.current == 0 { lastFilterMode = .off }
        cutoffLog.target = log2f(Float(DSP.clamp(master.filterCutoff, 20, 20_000)))
        let resonance = Float(master.filterResonance)
        if !primed {
            primed = true
            masterVolume.reset(to: masterVolume.target)
            delayMixSmooth.reset(to: delayMixSmooth.target)
            reverbMixSmooth.reset(to: reverbMixSmooth.target)
            filterWet.reset(to: filterWet.target)
            cutoffLog.reset(to: cutoffLog.target)
        }

        let modDepth = Float(master.modDepth)
        let modActive = modDepth > 0.0001
        let modTarget = master.modTarget
        let drive = Float(master.drive)
        let bits = Float(master.crushBits)
        let downsample = Float(master.crushDownsample)
        let crushActive = bits < 15.99 || downsample > 1.001
        let eqActive = !eq.isFlat
        let compActive = compressor.isActive
        var modValue: Float = 0
        var tremolo: Float = 1
        var (panL, panR): (Float, Float) = (1, 1)
        let sr = Float(sampleRate)

        for i in 0..<n {
            if (i & 15) == 0 {
                let cl = cutoffLog.next()
                if modActive {
                    modValue = modLFO.next(shape: master.modShape, rate: master.modRate, sampleRate: sampleRate, samples: 16)
                    switch modTarget {
                    case .tremolo: tremolo = 1 - modDepth * (0.5 + 0.5 * modValue)
                    case .pan: (panL, panR) = DSP.balanceGains(modValue * modDepth)
                    default: break
                    }
                } else {
                    tremolo = 1
                    panL = 1; panR = 1
                }
                if filterWet.current > 0 || filterWet.target > 0 {
                    var octaves = cl
                    if modActive && modTarget == .filter { octaves += modValue * modDepth * 3 }
                    masterFilter.setParameters(cutoff: exp2f(octaves), resonance: resonance, sampleRate: sr)
                }
            }
            var l = dryL[i] + wetDlyL[i] * delayMixSmooth.next() * 1.0
            var r = dryR[i] + wetDlyR[i] * delayMixSmooth.current
            let rv = reverbMixSmooth.next()
            l += wetRevL[i] * rv
            r += wetRevR[i] * rv

            let fw = filterWet.next()
            if fw > 0 {
                let (fl, fr) = masterFilter.process(l, r)
                l += (fl - l) * fw
                r += (fr - r) * fw
            }
            if drive > 0.0001 {
                l = Distortion.process(l, drive: drive)
                r = Distortion.process(r, drive: drive)
            }
            if crushActive { (l, r) = masterCrusher.process(l, r, bits: bits, downsample: downsample) }
            if modActive {
                switch modTarget {
                case .tremolo: l *= tremolo; r *= tremolo
                case .pan: l *= panL; r *= panR
                case .vibrato: (l, r) = vibrato.process(l, r, modulation: modValue * modDepth)
                case .filter: break
                }
            }
            if eqActive { (l, r) = eq.process(l, r) }
            if compActive { (l, r) = compressor.process(l, r) }
            let vol = masterVolume.next()
            outL[i] = l * vol + postL[i]
            outR[i] = r * vol + postR[i]
        }

        // Schutz vor NaN/Inf (z. B. durch extreme Resonanz) – Effekte zurücksetzen.
        let pk = max(VectorOps.peak(outL, count: n), VectorOps.peak(outR, count: n))
        if !pk.isFinite {
            resetEffects()
            VectorOps.clear(outL, count: n)
            VectorOps.clear(outR, count: n)
        }
        VectorOps.clip(outL, limit: 1, count: n)
        VectorOps.clip(outR, limit: 1, count: n)
    }

    private func resetEffects() {
        delay.reset()
        reverb.reset()
        vibrato.reset()
        masterFilter.reset()
        eq.reset()
        compressor.reset()
        for v in 0..<Self.physicalVoiceCount { voices[v].filter.reset() }
    }

    private func publishStatus(frames: Int, startTime: UInt64, outL: UnsafeMutablePointer<Float>, outR: UnsafeMutablePointer<Float>) {
        var active = 0
        for v in 0..<Self.physicalVoiceCount where voices[v].active && !voices[v].isFading { active += 1 }
        status.write(.activeVoices, Float(active))
        status.write(.transport, Float(sequencer.state.rawValue))
        status.write(.currentStep, Float(sequencer.displayStep))
        status.write(.currentPattern, Float(sequencer.currentSlot))
        status.write(.queuedPattern, Float(sequencer.queuedSlot))
        status.write(.positionSteps, Float(sequencer.position))
        status.write(.recording, isRecording ? 1 : 0)
        status.write(.gainReduction, compressor.currentGainReductionDb)
        let pl = VectorOps.peak(outL, count: frames)
        let pr = VectorOps.peak(outR, count: frames)
        status.write(.peakLeft, max(pl, status.read(.peakLeft) * 0.9))
        status.write(.peakRight, max(pr, status.read(.peakRight) * 0.9))
        for p in 0...Self.padCount {
            status.storage[EngineStatus.padLevelBase + p] = padLevels[p]
            padLevels[p] = 0
        }
        for p in 0..<Self.padCount {
            status.storage[EngineStatus.padTriggerBase + p] = padTriggers[p]
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- startTime) / 1e9
        let available = Double(frames) / sampleRate
        if available > 0 {
            let load = Float(elapsed / available)
            status.write(.load, status.read(.load) * 0.9 + load * 0.1)
        }
    }

    // MARK: - Befehle

    private func handle(_ command: EngineCommand) {
        switch command {
        case let .noteOn(pad, velocity):
            if sequencer.state == .playing && isRecording && (0..<Self.padCount).contains(pad) {
                recordHit(pad: pad, velocity: velocity)
            }
            startVoice(pad: pad, velocity: velocity, fromSequencer: false)
        case let .noteOnTransposed(pad, velocity, semitones):
            startVoice(pad: pad, velocity: velocity, fromSequencer: false, transpose: semitones)
        case let .noteOff(pad):
            releasePad(pad, fromSequencer: false)
        case .allNotesOff:
            for v in 0..<Self.physicalVoiceCount where voices[v].active { beginFade(voices + v, seconds: 0.01) }
        case let .setSample(pad, sample):
            guard (0..<Self.padCount).contains(pad) else { return }
            if let old = padSamples[pad] { _ = garbage.tryPush(old) }
            padSamples[pad] = sample
        case let .setPadSettings(pad, settings):
            guard (0..<Self.padCount).contains(pad) else { return }
            padSettings[pad] = settings
        case let .setMaster(settings):
            applyMaster(settings)
        case let .setEngineSettings(settings):
            engineSettings = settings
            engineSettings.polyphony = DSP.clamp(settings.polyphony, 1, EngineSettings.maximumPolyphony)
            enforcePolyphony()
        case let .setPattern(slot, pattern):
            if let old = sequencer.setPattern(pattern, slot: slot) { _ = garbage.tryPush(old) }
        case let .selectPattern(slot, immediately):
            sequencer.selectPattern(slot, immediately: immediately)
        case let .setTempo(bpm, swing):
            sequencer.bpm = DSP.clamp(bpm, 20, 400)
            sequencer.swing = DSP.clamp(swing, 50, 75)
        case let .setTrackStates(mutes, solos):
            sequencer.muteMask = mutes
            sequencer.soloMask = solos
        case let .transport(cmd):
            switch cmd {
            case .play: sequencer.play()
            case .pause:
                sequencer.pause()
                releaseSequencerVoices()
            case .stop:
                sequencer.stop()
                releaseSequencerVoices()
            }
        case let .setRecording(on):
            isRecording = on
        case let .setMetronome(on):
            sequencer.metronome = on
        case let .preview(sample, gain):
            previewGain = gain
            if let sample {
                if let old = previewVoice.sample, old !== sample { _ = garbage.tryPush(old) }
                startPreview(sample)
            } else if previewVoice.active {
                previewVoice.fadeStep = 1 / Float(0.01 * sampleRate)
            }
        }
    }

    private func applyMaster(_ s: MasterSettings) {
        master = s
        delay.feedback = Float(s.delayFeedback)
        delay.pingPong = s.delayPingPong
        delay.damping = Float(s.delayDamping)
        reverb.roomSize = Float(s.reverbSize)
        reverb.damping = Float(s.reverbDamping)
        reverb.width = Float(s.reverbWidth)
        eq.configure(lowDb: s.eqLow, midDb: s.eqMid, highDb: s.eqHigh, midFrequency: s.eqMidFrequency)
        compressor.thresholdDb = Float(s.compThreshold)
        compressor.ratio = Float(s.compRatio)
        compressor.attackSeconds = s.compAttack
        compressor.releaseSeconds = s.compRelease
        compressor.makeupDb = Float(s.compMakeup)
        compressor.updateTimes()
    }

    private func recordHit(pad: Int, velocity: Float) {
        let pos = sequencer.position
        lastManualHit[pad] = pos
        let len = max(sequencer.currentPatternLength, 1)
        let rel = pos - Double(sequencer.patternStartStep)
        let inPattern = rel - floor(rel / Double(len)) * Double(len)
        _ = events.tryPush(.recordedHit(pad: pad, velocity: velocity, slot: sequencer.currentSlot,
                                        positionInPattern: inPattern, patternLength: len))
    }

    private func handleSequencerEvent(_ e: SequencerEvent) {
        switch e.kind {
        case .noteOn:
            if isRecording && abs(e.time - lastManualHit[e.pad]) < 0.5 { return }
            startVoice(pad: e.pad, velocity: e.velocity, fromSequencer: true)
        case .noteOff:
            releasePad(e.pad, fromSequencer: true)
        case .click:
            clickFrequency = e.pad == 1 ? 1600 : 1000
            clickLength = Int(0.03 * sampleRate)
            clickRemaining = clickLength
            clickPhase = 0
        }
    }

    // MARK: - Stimmenverwaltung

    private func startVoice(pad: Int, velocity: Float, fromSequencer: Bool, transpose: Double = 0) {
        guard (0..<Self.padCount).contains(pad), let sample = padSamples[pad] else { return }
        let s = padSettings[pad]

        // Choke-Gruppen und Mono-Modus
        if s.chokeGroup > 0 || s.mono {
            for i in 0..<Self.physicalVoiceCount where voices[i].active && !voices[i].isFading {
                let other = voices[i].pad
                if (s.mono && other == pad) ||
                    (s.chokeGroup > 0 && other != pad && padSettings[other].chokeGroup == s.chokeGroup) {
                    beginFade(voices + i, seconds: 0.004)
                }
            }
        }

        // Polyphonie-Limit
        var activeCount = 0
        for i in 0..<Self.physicalVoiceCount where voices[i].active && !voices[i].isFading { activeCount += 1 }
        if activeCount >= engineSettings.polyphony {
            if engineSettings.stealMode == .none { return }
            if let victim = chooseVictim(forPad: pad) { beginFade(voices + victim, seconds: 0.003) }
        }

        // Freien Speicherplatz suchen
        var slot = -1
        for i in 0..<Self.physicalVoiceCount where !voices[i].active { slot = i; break }
        if slot < 0 {
            // Alle Plätze belegt: leiseste ausblendende oder älteste Stimme übernehmen.
            var best = 0
            var bestScore = Float.infinity
            for i in 0..<Self.physicalVoiceCount {
                let score = voices[i].isFading ? voices[i].fadeGain - 10 : Float(voices[i].age % 1_000_000)
                if score < bestScore { bestScore = score; best = i }
            }
            slot = best
            releaseVoiceSample(&voices[slot])
        }

        voiceCounter &+= 1
        var v = Voice()
        v.active = true
        v.pad = pad
        v.sample = sample
        v.age = voiceCounter
        v.fromSequencer = fromSequencer
        v.transpose = DSP.clamp(transpose, -48, 48)
        let frames = Double(sample.frameCount)
        let regionStart = DSP.clamp(s.start, 0, 1) * frames
        let regionEnd = max(DSP.clamp(s.end, 0, 1) * frames, regionStart + 2)
        let startPos = s.reverse ? min(regionEnd, frames) - 1 : regionStart
        v.position = startPos
        v.readHead = startPos
        v.grain0Start = startPos
        v.grain1Start = startPos
        v.grain0Phase = 0
        v.grain1Phase = -0.5
        v.firstGrain = true
        let vel = DSP.clamp(velocity, 0, 1)
        let sens = Float(DSP.clamp(s.velocitySensitivity, 0, 1))
        v.velocityGain = 1 - sens + sens * vel * vel
        v.gain = SmoothedValue(value: Float(s.volume) * v.velocityGain, timeSeconds: 0.005, sampleRate: sampleRate)
        v.envelope.configure(attack: s.attack, decay: s.decay, sustain: s.sustain, release: s.release, sampleRate: sampleRate)
        v.envelope.noteOn()
        v.lfo.reset()
        voices[slot] = v
        padTriggers[pad] += 1
    }

    private func startPreview(_ sample: SampleBuffer) {
        var v = Voice()
        v.active = true
        v.isPreview = true
        v.sample = sample
        v.velocityGain = 1
        v.gain = SmoothedValue(value: previewGain, timeSeconds: 0.005, sampleRate: sampleRate)
        v.envelope.configure(attack: 0.001, decay: 1, sustain: 1, release: 0.01, sampleRate: sampleRate)
        v.envelope.noteOn()
        previewVoice = v
    }

    private func chooseVictim(forPad pad: Int) -> Int? {
        var best = -1
        switch engineSettings.stealMode {
        case .none:
            return nil
        case .oldest, .samePad:
            var bestAge = UInt64.max
            if engineSettings.stealMode == .samePad {
                for i in 0..<Self.physicalVoiceCount
                where voices[i].active && !voices[i].isFading && voices[i].pad == pad && voices[i].age < bestAge {
                    bestAge = voices[i].age; best = i
                }
                if best >= 0 { return best }
            }
            for i in 0..<Self.physicalVoiceCount
            where voices[i].active && !voices[i].isFading && voices[i].age < bestAge {
                bestAge = voices[i].age; best = i
            }
        case .quietest:
            var bestLevel = Float.infinity
            for i in 0..<Self.physicalVoiceCount where voices[i].active && !voices[i].isFading {
                // Neu gestartete Stimmen (Level 0, noch nicht gerendert) gelten als laut.
                let level = voices[i].level == 0 ? 1 : voices[i].level
                if level < bestLevel { bestLevel = level; best = i }
            }
        }
        return best >= 0 ? best : nil
    }

    private func enforcePolyphony() {
        var activeCount = 0
        for i in 0..<Self.physicalVoiceCount where voices[i].active && !voices[i].isFading { activeCount += 1 }
        while activeCount > engineSettings.polyphony {
            guard let victim = chooseVictim(forPad: -1) ?? oldestVoice() else { break }
            beginFade(voices + victim, seconds: 0.003)
            activeCount -= 1
        }
    }

    private func oldestVoice() -> Int? {
        var best = -1
        var bestAge = UInt64.max
        for i in 0..<Self.physicalVoiceCount where voices[i].active && !voices[i].isFading && voices[i].age < bestAge {
            bestAge = voices[i].age; best = i
        }
        return best >= 0 ? best : nil
    }

    @inline(__always)
    private func beginFade(_ v: UnsafeMutablePointer<Voice>, seconds: Double) {
        guard v.pointee.active, !v.pointee.isFading else { return }
        v.pointee.fadeStep = 1 / Float(max(seconds, 0.0005) * sampleRate)
    }

    private func releasePad(_ pad: Int, fromSequencer: Bool) {
        guard (0..<Self.padCount).contains(pad) else { return }
        let mode = padSettings[pad].playMode
        guard mode != .oneShot else { return }
        for i in 0..<Self.physicalVoiceCount
        where voices[i].active && voices[i].pad == pad && voices[i].fromSequencer == fromSequencer && !voices[i].released {
            voices[i].envelope.noteOff()
            voices[i].released = true
        }
    }

    private func releaseSequencerVoices() {
        sequencer.discardPendingNotes()
        for i in 0..<Self.physicalVoiceCount where voices[i].active && voices[i].fromSequencer && !voices[i].released {
            if padSettings[voices[i].pad].playMode != .oneShot {
                voices[i].envelope.noteOff()
                voices[i].released = true
            }
        }
    }
}
