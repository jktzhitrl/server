import Foundation
import AppKit
import CoreAudio
import NexoraCore

/// Zustand der Aufnahme (Sampling / Resampling).
struct SamplingState: Equatable {
    enum Source: String, CaseIterable { case input, output }
    enum Phase: Equatable { case idle, armed, recording }

    var source: Source = .input
    /// Eingangsgerät (nil = Standard)
    var deviceID: AudioDeviceID?
    /// Startschwelle in dBFS (nil = sofort)
    var thresholdDb: Double?
    var maxSeconds: Double = 60
    var monitor = false
    /// Beim Resampling den Sequencer mit der Aufnahme starten und stoppen
    var startPlayback = true
    var targetPad = 0
    var phase: Phase = .idle
    var level: Float = 0
    var seconds: Double = 0

    var isActive: Bool { phase != .idle }
}

/// Letzter aufgezeichneter Motion-Wert (zum Auffüllen übersprungener Schritte).
struct MotionRecordPoint {
    var parameter: ParameterID
    var pad: Int
    var slot: Int
    var step: Int
    var value: Double
    var time: Date
}

/// Einstellungen des Slice-Dialogs.
struct SliceOptions: Equatable {
    enum Mode: String, CaseIterable { case transients, equal }
    var mode: Mode = .transients
    var count = 8
    var sensitivity = 0.5
    var startPad = 0
    var makePattern = true
}

extension SamplerController {
    // MARK: - Seiten (bis 64 Schritte)

    var pageCount: Int { (currentPattern.length + SequencerPattern.stepsPerPage - 1) / SequencerPattern.stepsPerPage }

    func setStepPage(_ page: Int, follow: Bool = false) {
        stepPage = min(max(page, 0), SequencerPattern.pageCount - 1)
        followPage = follow
        let first = stepPage * SequencerPattern.stepsPerPage
        showLCD("PAGE", "\(stepPage + 1)/\(SequencerPattern.pageCount) · STEPS \(first + 1)–\(first + SequencerPattern.stepsPerPage)", seconds: 1)
    }

    // MARK: - Song-Modus

    func sendSong() {
        let on = project.sequencer.songMode && !project.patternChain.isEmpty
        host.send(.setSong(on ? SongSnapshot(chain: project.patternChain) : nil))
    }

    func setSongMode(_ on: Bool) {
        project.sequencer.songMode = on
        if on && project.patternChain.isEmpty { project.patternChain = [project.sequencer.currentPattern] }
        sendSong()
        showLCD("SONG MODE", on ? "ON · \(project.patternChain.count) PATTERNS" : "OFF")
        markDirty()
    }

    func songChanged() {
        if project.sequencer.songMode { sendSong() }
        markDirty()
    }

    func songAppend(_ slot: Int) {
        guard project.patternChain.count < 64 else { showLCD("SONG", "FULL (64)"); return }
        project.patternChain.append(slot)
        showLCD("SONG", "+ \(SequencerState.slotName(slot)) · \(project.patternChain.count)", seconds: 1)
        songChanged()
    }

    func songRemove(at index: Int) {
        guard project.patternChain.indices.contains(index) else { return }
        project.patternChain.remove(at: index)
        songChanged()
    }

    func songMove(_ index: Int, by delta: Int) {
        let j = index + delta
        guard project.patternChain.indices.contains(index), project.patternChain.indices.contains(j) else { return }
        project.patternChain.swapAt(index, j)
        songChanged()
    }

    func songSetEntry(_ index: Int, slot: Int) {
        guard project.patternChain.indices.contains(index) else { return }
        project.patternChain[index] = slot
        songChanged()
    }

    func songClear() {
        project.patternChain = []
        songChanged()
        showLCD("SONG", "CLEARED")
    }

    /// Dauer der Song-Kette in Sekunden.
    var songDuration: Double {
        let steps = project.patternChain.reduce(0) { $0 + project.sequencer.patterns[$1].length }
        return Double(steps) * 60 / project.bpm / 4
    }

    // MARK: - Motion-Sequenz

    func setMotionMode(_ mode: MotionMode) {
        project.sequencer.motionMode = mode
        host.send(.setMotionMode(mode))
        showLCD("MOTION SEQ", mode.displayName)
        markDirty()
    }

    /// Zeichnet bei laufender Aufnahme Reglerbewegungen in das hörbare Pattern auf.
    func recordMotionValue(_ id: ParameterID, pad: Int) {
        guard isRecording, meters.transport == .playing, MotionLane.canRecord(id) else { return }
        let slot = meters.currentPattern, step = meters.currentStep
        guard project.sequencer.patterns.indices.contains(slot), step < project.sequencer.patterns[slot].length else { return }
        let value = project.value(of: id, pad: pad)
        let lanePad = id.isPadParameter ? pad : -1
        let now = Date()
        var from: MotionRecordPoint?
        if let last = motionLast, last.parameter == id, last.pad == lanePad, last.slot == slot,
           step > last.step, now.timeIntervalSince(last.time) < 0.6 {
            from = last
        }
        guard project.sequencer.patterns[slot].recordMotion(parameter: id, pad: pad, step: step, value: value,
                                                             fromStep: from?.step, fromValue: from?.value) else {
            showLCD("MOTION", "FULL (\(MotionLane.maxLanes) LANES)")
            return
        }
        motionLast = MotionRecordPoint(parameter: id, pad: lanePad, slot: slot, step: step, value: value, time: now)
        if !motionPushPending {
            motionPushPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.motionPushPending = false
                    self.pushPattern(slot)
                }
            }
        }
        markDirty()
    }

    func hasMotion(_ id: ParameterID, pad: Int? = nil) -> Bool {
        currentPattern.hasMotion(parameter: id, pad: pad ?? selectedPad)
    }

    func removeMotionLane(at index: Int) {
        let slot = project.sequencer.currentPattern
        guard project.sequencer.patterns[slot].motion.indices.contains(index) else { return }
        let lane = project.sequencer.patterns[slot].motion.remove(at: index)
        pushPattern(slot)
        showLCD("MOTION ERASED", lane.displayName)
        markDirty()
    }

    func removeMotion(_ id: ParameterID, pad: Int? = nil) {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].removeMotion(parameter: id, pad: pad ?? selectedPad)
        pushPattern(slot)
        markDirty()
    }

    func clearMotion() {
        let slot = project.sequencer.currentPattern
        project.sequencer.patterns[slot].motion = []
        pushPattern(slot)
        showLCD("PATTERN \(SequencerState.slotName(slot))", "MOTION CLEARED")
        markDirty()
    }

    // MARK: - Slice

    /// Slices, die `slice(_:)` mit diesen Einstellungen erzeugen würde (Vorschau).
    func previewSlices(_ o: SliceOptions) -> [SampleSlicer.Slice] {
        guard let sample = padSamples[selectedPad] else { return [] }
        let available = 16 - min(max(o.startPad, 0), 15)
        let st = project.pads[selectedPad].settings
        let mode: SampleSlicer.Mode = o.mode == .equal
            ? .equal(count: min(o.count, available))
            : .transients(sensitivity: o.sensitivity, maxSlices: available)
        return Array(SampleSlicer.slices(of: sample, mode: mode, regionStart: st.start, regionEnd: st.end).prefix(available))
    }

    /// Zerlegt das Sample des ausgewählten Pads und verteilt die Slices ab `startPad`.
    @discardableResult
    func slice(_ o: SliceOptions) -> Int {
        let src = selectedPad
        guard let sample = padSamples[src] else { showLCD("SLICE", "PAD IS EMPTY"); return 0 }
        let parts = previewSlices(o)
        guard !parts.isEmpty else { return 0 }
        let startPad = min(max(o.startPad, 0), 15)
        let source = project.pads[src]
        let url = padFileURLs[src]
        var base = source.name
        if let r = base.range(of: #"\s+\d+$"#, options: .regularExpression) { base.removeSubrange(r) }
        base = String(base.prefix(10))
        if base.isEmpty { base = "SLICE" }
        for (i, part) in parts.enumerated() {
            let t = startPad + i
            var settings = source.settings
            settings.start = part.start
            settings.end = part.end
            settings.reverse = false
            if settings.playMode == .loop { settings.playMode = .oneShot }
            project.pads[t].name = String("\(base) \(i + 1)".prefix(14))
            project.pads[t].settings = settings
            project.pads[t].sample = source.sample
            setPadSample(t, buffer: sample, fileURL: url)
            host.send(.setPadSettings(pad: t, settings: settings))
        }
        if o.makePattern {
            let slot = project.sequencer.currentPattern
            let steps = SampleSlicer.patternSteps(for: parts, length: project.sequencer.patterns[slot].length)
            for (i, step) in steps.enumerated() {
                let t = startPad + i
                project.sequencer.patterns[slot].clearTrack(t)
                project.sequencer.patterns[slot][t, step] = SequencerStep(active: true, velocity: 0.8)
            }
            pushPattern(slot)
        }
        selectedPad = startPad
        showLCD("SLICE", "\(parts.count) SLICES → PAD \(startPad + 1)–\(startPad + parts.count)", seconds: 2.5)
        markDirty()
        return parts.count
    }

    // MARK: - Sampling & Resampling

    func refreshInputDevices() {
        inputDevices = AudioDeviceManager.inputDevices()
    }

    func startSampling() {
        guard !sampling.isActive else { return }
        let o = sampling
        if o.source == .input {
            Task { @MainActor in
                guard await AudioInputRecorder.requestAccess() else {
                    self.report("Kein Zugriff auf das Mikrofon",
                                "Bitte erlauben Sie NEXORA Sampler den Zugriff unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon.")
                    return
                }
                self.beginCapture(o)
            }
        } else {
            beginCapture(o)
        }
    }

    private func beginCapture(_ o: SamplingState) {
        let options = SampleRecorder.Options(thresholdDb: o.thresholdDb, maxSeconds: o.maxSeconds)
        let recorder: SampleRecorder
        do {
            if o.source == .input {
                let input = inputRecorder ?? AudioInputRecorder()
                inputRecorder = input
                let rate = try input.prepare(device: o.deviceID)
                recorder = SampleRecorder(sampleRate: rate, options: options)
                try input.start(monitor: o.monitor) { l, r, n in recorder.append(left: l, right: r, count: n) }
            } else {
                recorder = SampleRecorder(sampleRate: host.sampleRate, options: options)
                host.installOutputTap { l, r, n in recorder.append(left: l, right: r, count: n) }
            }
        } catch {
            inputRecorder?.stop()
            report("Aufnahme nicht möglich", error.localizedDescription)
            return
        }
        activeRecorder = recorder
        sampling.phase = options.thresholdDb == nil ? .recording : .armed
        sampling.level = 0
        sampling.seconds = 0
        if o.source == .output && o.startPlayback && meters.transport != .playing {
            host.send(.transport(.stop))
            host.send(.transport(.play))
        }
        showLCD(o.source == .input ? "SAMPLING" : "RESAMPLING",
                options.thresholdDb == nil ? "RECORDING" : "WAITING FOR SIGNAL", seconds: 2)
    }

    func stopSampling() {
        guard sampling.isActive else { return }
        let source = sampling.source
        if source == .input { inputRecorder?.stop() } else { host.removeOutputTap() }
        if source == .output && sampling.startPlayback { host.send(.transport(.stop)) }
        let rec = activeRecorder
        activeRecorder = nil
        sampling.phase = .idle
        sampling.level = 0
        recordingCounter += 1
        let name = String(format: "%@ %02d", source == .input ? "REC" : "RESAMPLE", recordingCounter)
        guard let buffer = rec?.finish(name: name) else {
            showLCD("SAMPLING", "NOTHING RECORDED")
            return
        }
        assignNewSample(buffer, to: sampling.targetPad, name: name)
    }

    /// Rendert das aktuelle Pattern (ein Durchlauf, ohne Ausklang) und legt es als Sample auf ein Pad.
    func resamplePattern(to pad: Int? = nil) {
        guard !isResampling else { return }
        let target = pad ?? sampling.targetPad
        let slot = project.sequencer.currentPattern
        let request = OfflineRenderer.Request(sampleRate: host.sampleRate, document: project, samples: padSamples,
                                              patternOrder: [slot], loops: 1, tailSeconds: 0)
        isResampling = true
        showLCD("RESAMPLE", "PATTERN \(SequencerState.slotName(slot)) …", seconds: 3)
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = try? OfflineRenderer.render(request)
            await MainActor.run {
                guard let self else { return }
                self.isResampling = false
                guard let result else { self.report("Resampling fehlgeschlagen", "Das Pattern konnte nicht gerendert werden."); return }
                let name = "PTN \(SequencerState.slotName(slot)) RESMP"
                self.assignNewSample(OfflineRenderer.sampleBuffer(from: result, name: name), to: target, name: name)
            }
        }
    }

    func assignNewSample(_ buffer: SampleBuffer, to pad: Int, name: String) {
        guard (0..<16).contains(pad) else { return }
        project.pads[pad].name = String(name.prefix(14))
        project.pads[pad].settings.start = 0
        project.pads[pad].settings.end = 1
        project.pads[pad].settings.reverse = false
        project.pads[pad].sample = SampleReference(fileName: name + ".wav", frameCount: buffer.frameCount, sampleRate: buffer.sampleRate)
        setPadSample(pad, buffer: buffer, fileURL: nil)
        host.send(.setPadSettings(pad: pad, settings: project.pads[pad].settings))
        selectedPad = pad
        showLCD(String(format: "PAD %02d ← %@", pad + 1, name),
                String(format: "%.2fs %@", buffer.duration, buffer.isStereo ? "ST" : "MONO"), seconds: 2.5)
        markDirty()
    }
}
