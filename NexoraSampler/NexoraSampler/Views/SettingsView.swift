import SwiftUI
import NexoraCore

/// Einstellungsfenster (⌘,): Audio, Engine/Projekt, Pads & Tastatur, MIDI, Bibliothek.
struct SettingsView: View {
    var body: some View {
        TabView {
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2.fill") }
            ProjectSettingsTab()
                .tabItem { Label("Projekt", systemImage: "slider.horizontal.3") }
            PadSettingsTab()
                .tabItem { Label("Pads", systemImage: "square.grid.4x3.fill") }
            LibrarySettingsTab()
                .tabItem { Label("Bibliothek", systemImage: "folder.fill") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct AudioSettingsTab: View {
    @Environment(SamplerController.self) private var controller
    @AppStorage(PrefKey.bufferSize) private var bufferSize = 256
    @AppStorage(PrefKey.outputDeviceUID) private var deviceUID = ""

    var body: some View {
        Form {
            Picker("Ausgabegerät", selection: Binding(get: { deviceUID }, set: { uid in
                deviceUID = uid
                controller.selectOutputDevice(controller.outputDevices.first { $0.uid == uid })
            })) {
                Text("Systemstandard").tag("")
                ForEach(controller.outputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            Picker("Puffergröße", selection: Binding(get: { bufferSize }, set: { v in
                bufferSize = v
                controller.setBufferSize(UInt32(v))
            })) {
                ForEach(AudioDeviceManager.bufferSizeOptions, id: \.self) { size in
                    Text("\(size) Samples").tag(Int(size))
                }
            }
            LabeledContent("Abtastrate", value: String(format: "%.1f kHz", controller.host.sampleRate / 1000))
            LabeledContent("Latenz (geschätzt)", value: String(format: "%.1f ms", controller.host.estimatedLatencyMs))
            Text("Kleinere Puffer verringern die Latenz, erhöhen aber die CPU-Last. Für Live-Spiel werden 128–256 Samples empfohlen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Geräteliste aktualisieren") { controller.refreshOutputDevices() }
        }
        .formStyle(.grouped)
    }
}

private struct ProjectSettingsTab: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        Form {
            TextField("Projektname", text: Binding(get: { controller.project.name }, set: {
                controller.project.name = $0
                controller.markDirty()
            }))
            LabeledContent("Tempo") {
                HStack {
                    Slider(value: Binding(get: { controller.project.bpm }, set: { controller.setBPM(($0 * 10).rounded() / 10) }), in: 40...300)
                    Text(String(format: "%.1f BPM", controller.project.bpm)).monospacedDigit().frame(width: 80)
                }
            }
            LabeledContent("Swing") {
                HStack {
                    Slider(value: Binding(get: { controller.project.swing }, set: { controller.setParameterValue(.swing, value: $0.rounded()) }), in: 50...75)
                    Text(String(format: "%.0f %%", controller.project.swing)).monospacedDigit().frame(width: 80)
                }
            }
            Stepper("Polyphonie: \(controller.project.engine.polyphony) Stimmen",
                    value: Binding(get: { controller.project.engine.polyphony },
                                   set: { v in controller.updateEngineSettings { $0.polyphony = v } }),
                    in: 1...EngineSettings.maximumPolyphony)
            Picker("Voice-Stealing", selection: Binding(get: { controller.project.engine.stealMode },
                                                       set: { v in controller.updateEngineSettings { $0.stealMode = v } })) {
                Text("Älteste Stimme").tag(VoiceStealMode.oldest)
                Text("Leiseste Stimme").tag(VoiceStealMode.quietest)
                Text("Gleiches Pad zuerst").tag(VoiceStealMode.samePad)
                Text("Kein Stealing (neue Noten verwerfen)").tag(VoiceStealMode.none)
            }
            Picker("Standard-Exportrate", selection: Binding(get: { controller.project.export.sampleRate },
                                                            set: { controller.project.export.sampleRate = $0; controller.markDirty() })) {
                Text("44,1 kHz").tag(44_100.0)
                Text("48 kHz").tag(48_000.0)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PadSettingsTab: View {
    @AppStorage(PrefKey.velocityFromPosition) private var velocityFromPosition = true
    @AppStorage(PrefKey.keyboardVelocity) private var keyboardVelocity = 0.85
    @AppStorage(PrefKey.selectPadOnHit) private var selectOnHit = true
    @AppStorage(PrefKey.midiEnabled) private var midiEnabled = true
    @Environment(SamplerController.self) private var controller

    var body: some View {
        Form {
            Toggle("Anschlagstärke über Klickposition (oben = laut)", isOn: $velocityFromPosition)
            LabeledContent("Anschlagstärke Tastatur") {
                HStack {
                    Slider(value: $keyboardVelocity, in: 0.1...1)
                    Text("\(Int(keyboardVelocity * 127))").monospacedDigit().frame(width: 40)
                }
            }
            Toggle("Angeschlagenes Pad auswählen", isOn: $selectOnHit)
            Toggle("MIDI-Eingang aktiv", isOn: Binding(get: { midiEnabled }, set: {
                midiEnabled = $0
                controller.refreshMIDIRouting()
            }))
            Section("Tastenbelegung") {
                Text("1 2 3 4 / Q W E R / A S D F / Z X C V spielen die Pads 13–16 / 9–12 / 5–8 / 1–4. Leertaste: Play/Stop. Tasten können im Pad-Editor geändert werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LibrarySettingsTab: View {
    @AppStorage(PrefKey.copyImportsToLibrary) private var copyImports = true
    @AppStorage(PrefKey.autoPreview) private var autoPreview = true
    @AppStorage(PrefKey.previewVolume) private var previewVolume = 0.8
    @Environment(SamplerController.self) private var controller

    var body: some View {
        Form {
            Toggle("Importierte Dateien in die Bibliothek kopieren (empfohlen)", isOn: $copyImports)
            Toggle("Samples beim Auswählen automatisch vorhören", isOn: $autoPreview)
            LabeledContent("Lautstärke Vorhören") {
                Slider(value: $previewVolume, in: 0...1)
            }
            LabeledContent("Bibliotheksordner") {
                Button("Im Finder zeigen") { controller.revealInFinder(controller.library.root) }
            }
            Text(controller.library.root.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .formStyle(.grouped)
    }
}
