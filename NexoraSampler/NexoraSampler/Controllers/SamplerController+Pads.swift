import Foundation
import AppKit
import NexoraCore

extension SamplerController {
    // MARK: - Pads spielen

    func padDown(_ pad: Int, velocity: Float) {
        guard (0..<16).contains(pad) else { return }
        switch padMode {
        case .play:
            host.send(.noteOn(pad: pad, velocity: velocity))
            if AppPreferences.selectPadOnHit && selectedPad != pad { selectedPad = pad }
        case .step:
            toggleStep(track: selectedPad, step: stepPage * SequencerPattern.stepsPerPage + pad)
        case .keyboard:
            guard let semi = Self.keyboardSemitone(forPad: pad) else { return }
            keyboardHeldPads.insert(pad)
            host.send(.noteOnTransposed(pad: selectedPad, velocity: velocity, semitones: Double(semi + keyboardOctave * 12)))
        }
    }

    func padUp(_ pad: Int) {
        switch padMode {
        case .play:
            host.send(.noteOff(pad: pad))
        case .keyboard:
            keyboardHeldPads.remove(pad)
            if keyboardHeldPads.isEmpty { host.send(.noteOff(pad: selectedPad)) }
        case .step:
            break
        }
    }

    /// Keyboard-Modus: untere Reihe (Pads 9–16) = weiße Tasten C … C', obere Reihe (Pads 1–8) = schwarze Tasten.
    nonisolated static func keyboardSemitone(forPad pad: Int) -> Int? {
        let white = [0, 2, 4, 5, 7, 9, 11, 12]
        let black: [Int?] = [nil, 1, 3, nil, 6, 8, 10, nil]
        if pad >= 8 && pad < 16 { return white[pad - 8] }
        if pad >= 0 && pad < 8 { return black[pad] }
        return nil
    }

    func setPadMode(_ mode: PadMode) {
        if padMode == .keyboard && mode != .keyboard {
            keyboardHeldPads.removeAll()
            host.send(.noteOff(pad: selectedPad))
        }
        padMode = mode
        switch mode {
        case .play: showLCD("MODE", "TRIGGER", seconds: 1)
        case .step: showLCD("MODE", String(format: "SEQUENCER · PAD %02d", selectedPad + 1), seconds: 1.2)
        case .keyboard: showLCD("KEYBOARD", "\(project.pads[selectedPad].name) · OCT \(keyboardOctave)", seconds: 1.2)
        }
    }

    func toggleDrawer(_ panel: DrawerPanel) {
        drawer = drawer == panel ? nil : panel
    }

    /// „Exit“: schließt zuerst den Bereich, dann MIDI-Learn, dann Sondermodi der Pads.
    func exitAction() {
        if drawer != nil {
            drawer = nil
        } else if midiLearnActive {
            toggleMIDILearn()
        } else if padMode != .play {
            setPadMode(.play)
        }
    }

    func selectPad(_ pad: Int) {
        guard (0..<16).contains(pad) else { return }
        selectedPad = pad
        let info = padSamples[pad].map { String(format: "%.2fs", $0.duration) } ?? "EMPTY"
        showLCD(String(format: "PAD %02d", pad + 1), "\(project.pads[pad].name) · \(info)")
    }

    // MARK: - Samples laden

    /// Lädt eine Audiodatei asynchron auf ein Pad.
    func loadSample(from url: URL, into pad: Int, libraryItemID: UUID? = nil) {
        guard (0..<16).contains(pad) else { return }
        loadingPads.insert(pad)
        showLCD(String(format: "LOAD PAD %02d", pad + 1), url.deletingPathExtension().lastPathComponent.uppercased())
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let buffer = try AudioFileLoader.load(url: url)
                let overview = buffer.overview(bins: 320)
                await self?.assignLoadedSample(buffer, overview: overview, url: url, pad: pad, libraryItemID: libraryItemID)
            } catch {
                await self?.sampleLoadFailed(url: url, pad: pad, error: error)
            }
        }
    }

    private func sampleLoadFailed(url: URL, pad: Int, error: Error) {
        loadingPads.remove(pad)
        report("Sample konnte nicht geladen werden", "\(url.lastPathComponent): \(error.localizedDescription)")
    }

    private func assignLoadedSample(_ buffer: SampleBuffer, overview: [Float], url: URL, pad: Int, libraryItemID: UUID?) {
        loadingPads.remove(pad)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        project.pads[pad].sample = SampleReference(fileName: url.lastPathComponent, packagePath: nil, originalPath: url.path,
                                                   bookmark: bookmark, libraryItemID: libraryItemID, fileSize: size,
                                                   frameCount: buffer.frameCount, sampleRate: buffer.sampleRate)
        project.pads[pad].name = String(buffer.name.uppercased().prefix(14))
        project.pads[pad].settings.start = 0
        project.pads[pad].settings.end = 1
        padSamples[pad] = buffer
        padWaveforms[pad] = overview
        padFileURLs[pad] = url
        host.send(.setPadSettings(pad: pad, settings: project.pads[pad].settings))
        host.send(.setSample(pad: pad, sample: buffer))
        selectedPad = pad
        showLCD(String(format: "PAD %02d LOADED", pad + 1),
                String(format: "%@ %.1fk %@", project.pads[pad].name, buffer.sampleRate / 1000, buffer.isStereo ? "ST" : "MONO"))
        markDirty()
    }

    /// Setzt ein bereits dekodiertes Sample (Werks-Kit, Projekt laden).
    func setPadSample(_ pad: Int, buffer: SampleBuffer?, fileURL: URL?) {
        padSamples[pad] = buffer
        padWaveforms[pad] = buffer?.overview(bins: 320) ?? []
        padFileURLs[pad] = fileURL
        host.send(.setSample(pad: pad, sample: buffer))
    }

    func clearPad(_ pad: Int) {
        guard (0..<16).contains(pad) else { return }
        setPadSample(pad, buffer: nil, fileURL: nil)
        project.pads[pad].sample = nil
        project.pads[pad].name = "PAD \(pad + 1)"
        host.send(.setPadSettings(pad: pad, settings: project.pads[pad].settings))
        markDirty()
    }

    func renamePad(_ pad: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.pads[pad].name = String(trimmed.prefix(20))
        markDirty()
    }

    func setPadKey(_ pad: Int, key: String) {
        let k = String(key.lowercased().prefix(1))
        // Doppelte Belegung auflösen
        for i in project.pads.indices where i != pad && project.pads[i].keyboardKey == k && !k.isEmpty {
            project.pads[i].keyboardKey = ""
        }
        project.pads[pad].keyboardKey = k
        markDirty()
    }

    /// Öffnet einen Dateidialog und lädt ein Sample auf das ausgewählte Pad.
    func chooseSampleForSelectedPad() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(format: "Sample für Pad %02d auswählen", selectedPad + 1)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadSample(from: url, into: selectedPad)
    }

    /// Verarbeitet auf ein Pad gezogene Dateien (Finder oder Sample-Browser).
    func handleDrop(_ urls: [URL], onPad pad: Int) -> Bool {
        let audio = urls.filter { AudioFileLoader.isSupported($0) }
        guard !audio.isEmpty else {
            report("Nicht unterstütztes Format", "Unterstützt werden WAV, AIFF, MP3, M4A, CAF und FLAC.")
            return false
        }
        // Mehrere Dateien werden auf aufeinanderfolgende Pads verteilt.
        for (offset, url) in audio.prefix(16).enumerated() {
            let target = (pad + offset) % 16
            let libraryID = libraryItemID(forFileURL: url)
            loadSample(from: url, into: target, libraryItemID: libraryID)
        }
        return true
    }

    private func libraryItemID(forFileURL url: URL) -> UUID? {
        let path = url.standardizedFileURL.path
        for c in library.collections {
            for item in c.items where library.url(for: item)?.standardizedFileURL.path == path { return item.id }
        }
        return nil
    }

    // MARK: - Werks-Kit

    func loadFactoryKit(resetPatterns: Bool) {
        let sounds = FactoryKit.makeBuffers()
        for (i, entry) in sounds.enumerated() {
            project.pads[i].name = entry.0.name
            project.pads[i].settings = entry.1
            project.pads[i].sample = SampleReference(fileName: entry.0.name + ".wav")
            setPadSample(i, buffer: entry.0, fileURL: nil)
        }
        project.kitName = FactoryKit.kitName
        if resetPatterns {
            var seq = SequencerState()
            let demos = FactoryKit.demoPatterns()
            for (i, p) in demos.enumerated() { seq.patterns[i] = p }
            project.sequencer = seq
        }
        pushFullState()
        showLCD("KIT", FactoryKit.kitName.uppercased())
        markDirty()
    }

    // MARK: - Vorhören (Browser)

    func preview(url: URL) {
        previewTask?.cancel()
        let gain = AppPreferences.previewVolume
        previewTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let buffer = try? AudioFileLoader.load(url: url) else { return }
            if Task.isCancelled { return }
            await self?.startPreview(buffer, gain: gain)
        }
    }

    private func startPreview(_ buffer: SampleBuffer, gain: Float) {
        host.send(.preview(sample: buffer, gain: gain))
        showLCD("PREVIEW", String(format: "%@ %.2fs", buffer.name.uppercased(), buffer.duration))
    }

    func stopPreview() {
        previewTask?.cancel()
        host.send(.preview(sample: nil, gain: 1))
    }
}
