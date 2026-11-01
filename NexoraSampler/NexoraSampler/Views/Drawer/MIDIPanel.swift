import SwiftUI
import NexoraCore

/// MIDI: Geräte, Kanal, Pad-Noten, CC-Mappings und MIDI-Learn.
struct MIDIPanel: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        let midi = controller.project.midi
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                DrawerSection(title: "Eingänge") {
                    VStack(alignment: .leading, spacing: 4) {
                        if controller.midiSourceNames.isEmpty {
                            Text("Kein MIDI-Gerät angeschlossen").foregroundStyle(.secondary)
                        }
                        ForEach(controller.midiSourceNames, id: \.self) { name in
                            HStack(spacing: 6) {
                                LEDView(isOn: controller.meters.midiActivity, color: Nexora.Colors.turquoise, size: 5)
                                Text(name)
                            }
                        }
                        Button("Geräte neu suchen") { controller.midi.connectAllSources() }
                    }
                }
                DrawerSection(title: "Einstellungen") {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Kanal", selection: Binding(get: { midi.inputChannel },
                                                          set: { v in controller.updateMIDISettings { $0.inputChannel = v } })) {
                            Text("Omni").tag(0)
                            ForEach(1...16, id: \.self) { Text("Kanal \($0)").tag($0) }
                        }
                        .frame(width: 200)
                        Toggle("Start/Stop von MIDI übernehmen", isOn: Binding(get: { midi.respondToTransport },
                                                                              set: { v in controller.updateMIDISettings { $0.respondToTransport = v } }))
                        Toggle("Feste Anschlagstärke", isOn: Binding(get: { midi.fixedVelocity },
                                                                    set: { v in controller.updateMIDISettings { $0.fixedVelocity = v } }))
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(width: 250, alignment: .leading)

            DrawerSection(title: "Pad-Noten") {
                VStack(alignment: .leading, spacing: 4) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 6), count: 4), alignment: .leading, spacing: 4) {
                        ForEach(0..<16, id: \.self) { pad in
                            HStack(spacing: 4) {
                                Text(String(format: "%02d", pad + 1)).foregroundStyle(Nexora.Colors.turquoise)
                                Stepper(value: Binding(get: { max(midi.padNotes[pad], 0) },
                                                       set: { controller.assignNote($0, toPad: pad) }), in: 0...127) {
                                    Text(SamplerController.noteName(midi.padNotes[pad]))
                                        .font(Nexora.Fonts.value(9))
                                        .frame(width: 66, alignment: .leading)
                                }
                                .controlSize(.mini)
                            }
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 3)
                                .fill(controller.noteLearnPad == pad ? Nexora.Colors.pink.opacity(0.4) : Nexora.Colors.panel))
                            .onTapGesture(count: 2) { controller.noteLearnPad = pad }
                            .help("Doppelklick: Note per MIDI lernen")
                        }
                    }
                    Button("Standard (C1–D#2)") { controller.resetPadNotes() }
                }
            }

            DrawerSection(title: "CC-Zuordnungen") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(controller.midiLearnActive ? "Learn beenden" : "MIDI-Learn starten") { controller.toggleMIDILearn() }
                        if controller.midiLearnActive {
                            Text(controller.learnTarget.map { "Ziel: \($0.spec.name) – Controller bewegen" } ?? "Regler anklicken …")
                                .foregroundStyle(Nexora.Colors.pink)
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if midi.ccMappings.isEmpty {
                                Text("Noch keine Zuordnungen. MIDI-Learn starten, einen Regler anklicken und am Gerät einen Controller bewegen.")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 300, alignment: .leading)
                            }
                            ForEach(midi.ccMappings) { mapping in
                                HStack {
                                    Text("CC \(mapping.controller)").frame(width: 50, alignment: .leading)
                                    Text(mapping.channel == 0 ? "Alle" : "Ch \(mapping.channel)").frame(width: 40, alignment: .leading)
                                    Text(mapping.parameter.spec.name).frame(width: 160, alignment: .leading)
                                    Button {
                                        controller.removeMIDIMapping(id: mapping.id)
                                    } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain)
                                }
                                .font(Nexora.Fonts.value(10))
                            }
                        }
                    }
                    .frame(width: 320, height: 200)
                }
            }
        }
        .font(.system(size: 11))
    }
}
