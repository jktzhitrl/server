import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers
import NexoraCore

/// Modus der 16 Pads.
enum PadMode: String, CaseIterable {
    /// Pads spielen Samples
    case play
    /// Pads schalten die 16 Schritte der ausgewählten Spur (Step-Programmierung wie bei Hardware)
    case step
}

/// Ausklappbarer Bereich unterhalb des Instruments.
enum DrawerPanel: String, CaseIterable, Identifiable {
    case editor, sequencer, browser, effects, kits, midi
    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "PAD EDIT"
        case .sequencer: return "SEQUENCER"
        case .browser: return "SAMPLE BROWSER"
        case .effects: return "MASTER FX"
        case .kits: return "KITS & PRESETS"
        case .midi: return "MIDI"
        }
    }
}

/// Kurzzeitige Meldung im LCD (z. B. beim Drehen eines Reglers).
struct LCDMessage: Equatable {
    var title: String
    var value: String
    var expires: Date
}

/// Benutzerhinweis (Fehler oder Information) als Alert.
struct UserNotice: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
}

extension UTType {
    static let nexoraProject = UTType(exportedAs: "de.nexora.sampler.project", conformingTo: .package)
    static let nexoraKit = UTType(exportedAs: "de.nexora.sampler.kit", conformingTo: .package)
}

/// Zentrale Steuerung der App: hält das Projektmodell, synchronisiert es mit der
/// Audio-Engine und stellt alle Aktionen für die Benutzeroberfläche bereit.
@MainActor
@Observable
final class SamplerController {
    // MARK: Modell
    var project: ProjectDocument
    /// Dekodierte Samples je Pad
    var padSamples: [SampleBuffer?] = Array(repeating: nil, count: 16)
    /// Wellenform-Übersichten je Pad
    var padWaveforms: [[Float]] = Array(repeating: [], count: 16)
    /// Datei, aus der das Pad-Sample stammt (Quelle beim Speichern)
    @ObservationIgnored var padFileURLs: [URL?] = Array(repeating: nil, count: 16)

    // MARK: UI-Zustand
    var selectedPad = 0
    var padMode: PadMode = .play
    var drawer: DrawerPanel?
    var isRecording = false
    var lcdMessage: LCDMessage?
    var midiLearnActive = false
    var learnTarget: ParameterID?
    /// Pad, dessen MIDI-Note per Learn zugewiesen wird
    var noteLearnPad: Int?
    var xyLatch = true
    var projectURL: URL?
    var isDirty = false
    var notice: UserNotice?
    var showExportSheet = false
    var exportProgress: Double?
    var midiSourceNames: [String] = []
    var outputDevices: [AudioOutputDevice] = []
    var loadingPads: Set<Int> = []
    /// Fortschritt der Installation der Werks-Bibliothek (nil = nicht aktiv)
    var factoryInstallProgress: Double?
    /// Automatischer Screenshot-Modus (keine Dialoge)
    var screenshotMode = false

    // MARK: Dienste
    let host: AudioEngineHost
    let midi = MIDIManager()
    let routing = MIDIRouting()
    let presets: PresetStore
    let meters = MeterModel()
    let library: LibraryModel
    var presetRevision = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var heldKeys: [UInt16: Int] = [:]
    @ObservationIgnored var patternClipboard: SequencerPattern?
    @ObservationIgnored var tapTimes: [Date] = []
    @ObservationIgnored var previewTask: Task<Void, Never>?
    @ObservationIgnored var pumpTimer: Timer?
    @ObservationIgnored var pumpLeft: UnsafeMutablePointer<Float>?
    @ObservationIgnored var pumpRight: UnsafeMutablePointer<Float>?
    let exportCancellation = CancellationFlag()

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("NEXORA Sampler", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        AppPreferences.registerDefaults()
        host = AudioEngineHost()
        presets = PresetStore(root: Self.supportDirectory.appendingPathComponent("Presets", isDirectory: true))
        library = LibraryModel(root: Self.supportDirectory.appendingPathComponent("Library", isDirectory: true))
        project = ProjectDocument(name: "Untitled")

        host.onEngineRebuilt = { [weak self] _ in
            MainActor.assumeIsolated { self?.pushFullState() }
        }
        host.onError = { [weak self] message in
            MainActor.assumeIsolated { self?.report("Audio", message) }
        }
        host.preferredBufferSizeFromPreferences()
        restoreOutputDevice()
        host.start()
        outputDevices = AudioDeviceManager.outputDevices()

        loadFactoryKit(resetPatterns: true)
        isDirty = false
        setupMIDI()
        startTimer()
        installKeyboardMonitor()
        installFactoryLibraryIfNeeded()
    }

    // MARK: - Engine-Synchronisation

    /// Überträgt den kompletten Projektzustand an die Engine (nach Laden oder Neuaufbau).
    func pushFullState() {
        for i in 0..<16 {
            host.send(.setPadSettings(pad: i, settings: project.pads[i].settings))
            host.send(.setSample(pad: i, sample: padSamples[i]))
        }
        host.send(.setMaster(project.master))
        host.send(.setEngineSettings(project.engine))
        host.send(.setTempo(bpm: project.bpm, swing: project.swing))
        sendTrackStates()
        for slot in 0..<SequencerState.patternSlots { pushPattern(slot) }
        host.send(.selectPattern(slot: project.sequencer.currentPattern, immediately: true))
        host.send(.setMetronome(project.sequencer.metronome))
        host.send(.setRecording(isRecording))
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
    }

    func pushPattern(_ slot: Int) {
        host.send(.setPattern(slot: slot, pattern: PatternSnapshot(project.sequencer.patterns[slot])))
    }

    func sendTrackStates() {
        host.send(.setTrackStates(mutes: project.sequencer.muteMask, solos: project.sequencer.soloMask))
    }

    private func apply(_ scope: ParameterScope) {
        switch scope {
        case .pad(let i): host.send(.setPadSettings(pad: i, settings: project.pads[i].settings))
        case .master: host.send(.setMaster(project.master))
        case .tempo: host.send(.setTempo(bpm: project.bpm, swing: project.swing))
        }
    }

    func markDirty() {
        if !isDirty { isDirty = true }
    }

    // MARK: - Parameter

    func normalizedValue(_ id: ParameterID, pad: Int? = nil) -> Double {
        project.normalizedValue(of: id, pad: pad ?? selectedPad)
    }

    func displayValue(_ id: ParameterID, pad: Int? = nil) -> String {
        id.spec.format(project.value(of: id, pad: pad ?? selectedPad))
    }

    /// Zentrale Änderung eines Parameters (Regler, XY-Pad, MIDI-CC). Sofort hörbar.
    func setParameter(_ id: ParameterID, normalized: Double, pad: Int? = nil, showOnLCD: Bool = true) {
        let target = pad ?? selectedPad
        let scope = project.setNormalizedValue(normalized, for: id, pad: target)
        apply(scope)
        if showOnLCD { showParameter(id, pad: target) }
        markDirty()
    }

    func setParameterValue(_ id: ParameterID, value: Double, pad: Int? = nil) {
        let target = pad ?? selectedPad
        apply(project.setValue(value, for: id, pad: target))
        showParameter(id, pad: target)
        markDirty()
    }

    func showParameter(_ id: ParameterID, pad: Int? = nil) {
        let target = pad ?? selectedPad
        let prefix = id.isPadParameter ? String(format: "P%02d ", target + 1) : ""
        showLCD(prefix + id.spec.name.uppercased(), id.spec.format(project.value(of: id, pad: target)))
    }

    func showLCD(_ title: String, _ value: String, seconds: Double = 1.6) {
        lcdMessage = LCDMessage(title: title, value: value, expires: Date().addingTimeInterval(seconds))
    }

    /// Ändert Pad-Einstellungen, die keine Regler sind (Modus, Reverse, Filtertyp …).
    func updatePad(_ index: Int, _ body: (inout PadConfig) -> Void) {
        guard (0..<16).contains(index) else { return }
        body(&project.pads[index])
        host.send(.setPadSettings(pad: index, settings: project.pads[index].settings))
        markDirty()
    }

    func updateMaster(_ body: (inout MasterSettings) -> Void) {
        body(&project.master)
        host.send(.setMaster(project.master))
        markDirty()
    }

    func updateEngineSettings(_ body: (inout EngineSettings) -> Void) {
        body(&project.engine)
        host.send(.setEngineSettings(project.engine))
        showLCD("POLYPHONY", "\(project.engine.polyphony) · \(project.engine.stealMode.shortName)")
        markDirty()
    }

    // MARK: - XY-Pad

    func setXY(x: Double, y: Double) {
        setParameter(project.xyPad.xParameter, normalized: x, showOnLCD: false)
        setParameter(project.xyPad.yParameter, normalized: y, showOnLCD: false)
        let xs = project.xyPad.xParameter.spec, ys = project.xyPad.yParameter.spec
        showLCD("X \(xs.shortName) · Y \(ys.shortName)",
                "\(displayValue(project.xyPad.xParameter)) / \(displayValue(project.xyPad.yParameter))", seconds: 1)
    }

    func assignXY(axis: XYAxis, parameter: ParameterID) {
        switch axis {
        case .x: project.xyPad.xParameter = parameter
        case .y: project.xyPad.yParameter = parameter
        }
        showLCD("XY \(axis == .x ? "X" : "Y")-AXIS", parameter.spec.name.uppercased())
        markDirty()
    }

    // MARK: - Laufende Aktualisierung (30 Hz)

    private func startTimer() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let status = host.sampler.status
        meters.update(from: status)
        host.sampler.drainGarbage()
        host.sampler.pollEvents { [weak self] event in self?.handleEngineEvent(event) }
        if meters.transport == .playing, meters.currentPattern != project.sequencer.currentPattern,
           (0..<SequencerState.patternSlots).contains(meters.currentPattern) {
            project.sequencer.currentPattern = meters.currentPattern
        }
        if let progress = factoryInstallProgress {
            lcdMessage = LCDMessage(title: "INSTALLING SOUND LIBRARY", value: "\(Int(progress * 100))%  ·  \(FactoryLibrary.sounds.count) SOUNDS",
                                    expires: Date().addingTimeInterval(0.5))
        } else if let msg = lcdMessage, msg.expires < Date() {
            lcdMessage = nil
        }
    }

    private func handleEngineEvent(_ event: EngineEvent) {
        switch event {
        case let .recordedHit(pad, velocity, slot, position, length):
            guard project.sequencer.patterns.indices.contains(slot) else { return }
            let placement = Quantizer.place(position: position, length: length,
                                            mode: project.sequencer.quantize, swing: project.swing)
            project.sequencer.patterns[slot][pad, placement.step] =
                SequencerStep(active: true, velocity: Double(velocity), offset: placement.offset)
            pushPattern(slot)
            markDirty()
        }
    }

    // MARK: - Tastatur

    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKeyEvent(event) }
            return handled ? nil : event
        }
    }

    /// Liefert `true`, wenn das Ereignis verarbeitet wurde.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Texteingaben und Tastenkürzel mit ⌘/⌃/⌥ nicht abfangen.
        if let responder = event.window?.firstResponder, responder is NSTextView { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) { return false }
        guard event.window?.isKeyWindow ?? true, NSApp.modalWindow == nil else { return false }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return false }

        if event.type == .keyDown && chars == " " {
            if !event.isARepeat { togglePlay() }
            return true
        }
        if event.type == .keyUp, let pad = heldKeys.removeValue(forKey: event.keyCode) {
            padUp(pad)
            return true
        }
        guard event.type == .keyDown else { return false }
        guard let pad = project.pads.firstIndex(where: { $0.keyboardKey.lowercased() == chars }) else { return false }
        if event.isARepeat { return true }
        heldKeys[event.keyCode] = pad
        padDown(pad, velocity: AppPreferences.keyboardVelocity)
        return true
    }

    // MARK: - Hinweise

    func report(_ title: String, _ message: String) {
        guard !screenshotMode else {
            print("[NEXORA] \(title): \(message)")
            return
        }
        notice = UserNotice(title: title, message: message)
    }
}

enum XYAxis { case x, y }

/// Thread-sicheres Abbruch-Flag für den Export.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

extension AudioEngineHost {
    func preferredBufferSizeFromPreferences() {
        applyBufferSize(AppPreferences.bufferSize)
    }
}

extension SamplerController {
    func restoreOutputDevice() {
        guard let uid = AppPreferences.outputDeviceUID,
              let device = AudioDeviceManager.outputDevices().first(where: { $0.uid == uid }) else { return }
        host.selectOutputDevice(device.id)
    }

    func selectOutputDevice(_ device: AudioOutputDevice?) {
        UserDefaults.standard.set(device?.uid, forKey: PrefKey.outputDeviceUID)
        host.selectOutputDevice(device?.id)
        outputDevices = AudioDeviceManager.outputDevices()
    }

    func setBufferSize(_ frames: UInt32) {
        UserDefaults.standard.set(Int(frames), forKey: PrefKey.bufferSize)
        host.applyBufferSize(frames)
        showLCD("BUFFER", "\(frames) · \(String(format: "%.1f ms", host.estimatedLatencyMs))")
    }

    func refreshOutputDevices() {
        outputDevices = AudioDeviceManager.outputDevices()
    }
}
