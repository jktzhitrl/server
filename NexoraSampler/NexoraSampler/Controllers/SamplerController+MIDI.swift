import Foundation
import NexoraCore

extension SamplerController {
    /// Richtet Core MIDI ein. Noten werden direkt im MIDI-Thread an die Engine geschickt
    /// (geringste Latenz); Controller, Transport und MIDI-Learn laufen auf dem Haupt-Thread.
    func setupMIDI() {
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
        let forward: @Sendable (MIDIMessage) -> Void = { [weak self] message in
            Task { @MainActor in self?.handleMIDIOnMain(message) }
        }
        midi.onMessage = Self.makeRealtimeMIDIHandler(routing: routing, host: host, forward: forward)
        midi.onSourcesChanged = { [weak self] names in
            MainActor.assumeIsolated { self?.midiSourceNames = names }
        }
        if let error = midi.start() {
            report("MIDI", error)
        }
        midiSourceNames = midi.sourceNames
    }

    nonisolated static func makeRealtimeMIDIHandler(routing: MIDIRouting, host: AudioEngineHost,
                                                    forward: @escaping @Sendable (MIDIMessage) -> Void) -> (MIDIMessage) -> Void {
        return { message in
            let (settings, enabled) = routing.snapshot()
            guard enabled else { return }
            switch message {
            case let .noteOn(channel, note, velocity):
                if settings.accepts(channel: channel), let pad = settings.pad(forNote: note) {
                    let v: Float = settings.fixedVelocity ? 1 : Float(velocity) / 127
                    host.send(.noteOn(pad: pad, velocity: v))
                }
            case let .noteOff(channel, note, _):
                if settings.accepts(channel: channel), let pad = settings.pad(forNote: note) {
                    host.send(.noteOff(pad: pad))
                }
            default:
                break
            }
            forward(message)
        }
    }

    func handleMIDIOnMain(_ message: MIDIMessage) {
        meters.noteMIDIActivity()
        guard AppPreferences.midiEnabled else { return }
        switch message {
        case let .noteOn(channel, note, _):
            guard project.midi.accepts(channel: channel) else { return }
            if let pad = noteLearnPad {
                assignNote(note, toPad: pad)
                noteLearnPad = nil
            } else if let pad = project.midi.pad(forNote: note), AppPreferences.selectPadOnHit, padMode == .play {
                if selectedPad != pad { selectedPad = pad }
            }
        case let .controlChange(channel, controller, value):
            if midiLearnActive, let target = learnTarget {
                project.midi.learn(controller: controller, channel: channel, parameter: target)
                routing.update(project.midi, enabled: AppPreferences.midiEnabled)
                showLCD("MIDI LEARN", "CC\(controller) CH\(channel) → \(target.spec.shortName)", seconds: 2.5)
                learnTarget = nil
                markDirty()
                return
            }
            guard project.midi.accepts(channel: channel) else { return }
            for mapping in project.midi.mappings(controller: controller, channel: channel) {
                setParameter(mapping.parameter, normalized: Double(value) / 127, pad: mapping.padIndex)
            }
        case .start:
            if project.midi.respondToTransport { play() }
        case .continue:
            if project.midi.respondToTransport { play() }
        case .stop:
            if project.midi.respondToTransport { stop() }
        default:
            break
        }
    }

    func toggleMIDILearn() {
        midiLearnActive.toggle()
        learnTarget = nil
        noteLearnPad = nil
        showLCD("MIDI LEARN", midiLearnActive ? "TOUCH A KNOB, MOVE A CC" : "OFF", seconds: 2.5)
    }

    func beginLearn(for parameter: ParameterID) {
        midiLearnActive = true
        learnTarget = parameter
        showLCD("MIDI LEARN", "\(parameter.spec.shortName): MOVE A CONTROLLER", seconds: 3)
    }

    func removeMIDIMapping(for parameter: ParameterID) {
        project.midi.removeMappings(for: parameter)
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
        markDirty()
    }

    func removeMIDIMapping(id: UUID) {
        project.midi.ccMappings.removeAll { $0.id == id }
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
        markDirty()
    }

    func assignNote(_ note: Int, toPad pad: Int) {
        // Eine Note gehört genau einem Pad.
        for i in project.midi.padNotes.indices where project.midi.padNotes[i] == note && i != pad {
            project.midi.padNotes[i] = -1
        }
        project.midi.padNotes[pad] = min(max(note, 0), 127)
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
        showLCD(String(format: "PAD %02d NOTE", pad + 1), Self.noteName(note))
        markDirty()
    }

    func updateMIDISettings(_ body: (inout MIDISettings) -> Void) {
        body(&project.midi)
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
        markDirty()
    }

    func resetPadNotes() {
        updateMIDISettings { $0.padNotes = (0..<16).map { MIDISettings.defaultBaseNote + $0 } }
    }

    func refreshMIDIRouting() {
        routing.update(project.midi, enabled: AppPreferences.midiEnabled)
    }

    nonisolated static func noteName(_ note: Int) -> String {
        guard (0...127).contains(note) else { return "—" }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[note % 12])\(note / 12 - 2) (\(note))"
    }
}
