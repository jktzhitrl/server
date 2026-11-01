import SwiftUI
import NexoraCore

/// Dialog für den Audioexport (WAV/AIFF, 44,1/48 kHz, Stereo).
struct ExportSheet: View {
    @Environment(SamplerController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()
    @State private var chainText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audio exportieren")
                .font(.title2.bold())
            Text("Das Pattern wird offline mit der gleichen Audio-Engine gerendert, die Sie hören – inklusive aller Pad- und Master-Effekte.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Format", selection: $settings.format) {
                    Text("WAV").tag(ExportFileFormat.wav)
                    Text("AIFF").tag(ExportFileFormat.aiff)
                }
                .pickerStyle(.segmented)
                Picker("Abtastrate", selection: $settings.sampleRate) {
                    Text("44,1 kHz").tag(44_100.0)
                    Text("48 kHz").tag(48_000.0)
                }
                .pickerStyle(.segmented)
                Picker("Bittiefe", selection: $settings.bitDepth) {
                    ForEach(ExportBitDepth.allCases, id: \.self) { depth in
                        Text(depth.displayName).tag(depth)
                    }
                }
                .pickerStyle(.segmented)
                if settings.format == .aiff && settings.bitDepth == .float32 {
                    Text("AIFF wird mit 16 oder 24 Bit geschrieben – bitte Bittiefe wählen.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Stepper("Wiederholungen: \(settings.loops)×", value: $settings.loops, in: 1...64)
                Stepper(String(format: "Ausklingzeit: max. %.0f s", settings.tailSeconds), value: $settings.tailSeconds, in: 0...30, step: 1)
                Toggle("Pattern-Kette exportieren", isOn: $settings.exportChain)
                if settings.exportChain {
                    TextField("Kette (z. B. A A B A)", text: $chainText)
                        .onSubmit { applyChain() }
                    Text("Aktuelle Kette: " + controller.project.patternChain.map { SequencerState.slotName($0) }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Auf −0,3 dBFS normalisieren", isOn: $settings.normalize)
                LabeledContent("Kanäle", value: "Stereo")
            }
            .formStyle(.grouped)
            if let progress = controller.exportProgress {
                ProgressView(value: progress) { Text("Rendere …") }
            }
            HStack {
                Spacer()
                if controller.exportProgress != nil {
                    Button("Abbrechen") { controller.cancelExport() }
                } else {
                    Button("Schließen") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Exportieren …") {
                    applyChain()
                    controller.exportAudio(with: settings)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(controller.exportProgress != nil || (settings.format == .aiff && settings.bitDepth == .float32))
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            settings = controller.project.export
            chainText = controller.project.patternChain.map { SequencerState.slotName($0) }.joined(separator: " ")
        }
    }

    private func applyChain() {
        let letters = Array("ABCDEFGHIJKLMNOP")
        let slots = chainText.uppercased().compactMap { ch -> Int? in
            guard let i = letters.firstIndex(of: ch), i < SequencerState.patternSlots else { return nil }
            return i
        }
        if !slots.isEmpty { controller.setPatternChain(slots) }
    }
}
