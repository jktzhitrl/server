import Foundation
import NexoraCore

extension SamplerController {
    // MARK: - Transport

    var isPlaying: Bool { meters.transport == .playing }

    func play() {
        host.send(.transport(.play))
        showLCD("PLAY", "PATTERN \(SequencerState.slotName(project.sequencer.currentPattern))", seconds: 0.8)
    }

    func pause() {
        host.send(.transport(.pause))
        showLCD("PAUSE", "", seconds: 0.8)
    }

    func stop() {
        host.send(.transport(.stop))
        showLCD("STOP", "", seconds: 0.8)
    }

    func togglePlay() {
        if meters.transport == .playing { stop() } else { play() }
    }

    func toggleRecord() {
        isRecording.toggle()
        host.send(.setRecording(isRecording))
        showLCD("RECORD", isRecording ? "ARMED · Q \(project.sequencer.quantize.shortName)" : "OFF")
        if isRecording && meters.transport != .playing { play() }
    }

    func toggleMetronome() {
        project.sequencer.metronome.toggle()
        host.send(.setMetronome(project.sequencer.metronome))
        showLCD("METRONOME", project.sequencer.metronome ? "ON" : "OFF")
        markDirty()
    }

    func setBPM(_ bpm: Double) {
        setParameterValue(.tempo, value: bpm)
    }

    /// Tap-Tempo: Mittelwert der letzten Abstände.
    func tapTempo() {
        let now = Date()
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < 2.5 }
        tapTimes.append(now)
        guard tapTimes.count >= 2 else {
            showLCD("TAP", "…", seconds: 1)
            return
        }
        let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        setBPM((60 / average * 10).rounded() / 10)
    }

    // MARK: - Patterns

    var currentPattern: SequencerPattern { project.currentPattern }

    func selectPattern(_ slot: Int) {
        guard (0..<SequencerState.patternSlots).contains(slot) else { return }
        patternBank = slot / 4
        let immediate = meters.transport != .playing || !project.sequencer.switchAtBarEnd
        host.send(.selectPattern(slot: slot, immediately: immediate))
        if immediate {
            project.sequencer.currentPattern = slot
            showLCD("PATTERN", SequencerState.slotName(slot))
        } else {
            showLCD("NEXT PATTERN", "\(SequencerState.slotName(slot)) AT BAR END")
        }
        markDirty()
    }

    func stepPattern(by delta: Int) {
        let n = SequencerState.patternSlots
        let slot = ((project.sequencer.currentPattern + delta) % n + n) % n
        patternBank = slot / 4
        selectPattern(slot)
    }

    func toggleStep(track: Int, step: Int) {
        let slot = project.sequencer.currentPattern
        guard step < project.sequencer.patterns[slot].length else { return }
        let velocity = Double(AppPreferences.keyboardVelocity)
        project.sequencer.patterns[slot].toggle(track: track, step: step, velocity: velocity)
        pushPattern(slot)
        let on = project.sequencer.patterns[slot][track, step].active
        showLCD(String(format: "STEP %02d · %@", step + 1, project.pads[track].name), on ? "ON" : "OFF", seconds: 0.9)
        markDirty()
    }

    /// Wechselt die Anschlagstärke eines aktiven Schritts (100 % → 70 % → 40 %).
    func cycleStepVelocity(track: Int, step: Int) {
        let slot = project.sequencer.currentPattern
        var s = project.sequencer.patterns[slot][track, step]
        guard s.active else { toggleStep(track: track, step: step); return }
        s.velocity = s.velocity > 0.85 ? 0.7 : (s.velocity > 0.55 ? 0.4 : 1.0)
        project.sequencer.patterns[slot][track, step] = s
        pushPattern(slot)
        showLCD(String(format: "STEP %02d VELOCITY", step + 1), "\(Int(s.velocity * 100))%", seconds: 0.9)
        markDirty()
    }

    func setPatternLength(_ length: Int) {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].length = min(max(length, 1), SequencerPattern.maxSteps)
        pushPattern(slot)
        showLCD("PATTERN LENGTH", "\(project.sequencer.patterns[slot].length) STEPS")
        markDirty()
    }

    func setTrackGate(_ track: Int, steps: Double) {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].gates[track] = min(max(steps, 0.25), 16)
        pushPattern(slot)
        markDirty()
    }

    func clearCurrentPattern() {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].clear()
        pushPattern(slot)
        showLCD("PATTERN \(SequencerState.slotName(slot))", "CLEARED")
        markDirty()
    }

    func clearTrack(_ track: Int) {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].clearTrack(track)
        pushPattern(slot)
        markDirty()
    }

    func copyPattern() {
        patternClipboard = currentPattern
        showLCD("COPY", "PATTERN \(SequencerState.slotName(project.sequencer.currentPattern))")
    }

    func pastePattern() {
        guard var p = patternClipboard else { return }
        let slot = project.sequencer.currentPattern
        p.id = UUID()
        p.name = "Pattern \(SequencerState.slotName(slot))"
        project.sequencer.patterns[slot] = p
        pushPattern(slot)
        showLCD("PASTE", "PATTERN \(SequencerState.slotName(slot))")
        markDirty()
    }

    func quantizeCurrentPattern() {
        let slot = project.sequencer.currentPattern
        let mode = project.sequencer.quantize == .off ? QuantizeMode.sixteenth : project.sequencer.quantize
        project.sequencer.patterns[slot] = Quantizer.quantize(project.sequencer.patterns[slot], mode: mode)
        pushPattern(slot)
        showLCD("QUANTIZE", mode.shortName)
        markDirty()
    }

    func setQuantize(_ mode: QuantizeMode) {
        project.sequencer.quantize = mode
        showLCD("REC QUANTIZE", mode.shortName)
        markDirty()
    }

    func toggleMute(_ track: Int) {
        project.sequencer.trackMutes[track].toggle()
        sendTrackStates()
        markDirty()
    }

    func toggleSolo(_ track: Int) {
        project.sequencer.trackSolos[track].toggle()
        sendTrackStates()
        markDirty()
    }

    func setSwitchAtBarEnd(_ value: Bool) {
        project.sequencer.switchAtBarEnd = value
        markDirty()
    }

    func setPatternChain(_ chain: [Int]) {
        project.patternChain = chain.filter { (0..<SequencerState.patternSlots).contains($0) }
        markDirty()
    }
}
