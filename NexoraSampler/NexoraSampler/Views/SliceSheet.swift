import SwiftUI
import NexoraCore

/// Slice-Dialog: Sample in Stücke zerlegen und auf Pads verteilen.
struct SliceSheet: View {
    @Environment(SamplerController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var options = SliceOptions()
    @State private var didInit = false

    var body: some View {
        let src = controller.selectedPad
        let config = controller.project.pads[src]
        VStack(alignment: .leading, spacing: 12) {
            Text("Slice – Pad \(src + 1): \(config.name)").font(.headline)
            if controller.padSamples[src] == nil {
                Text("Das ausgewählte Pad ist leer. Laden Sie zuerst ein Sample oder einen Song auf das Pad.")
                HStack { Spacer(); Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else {
                Text("Zerlegt das Sample (z. B. einen Drum-Loop oder einen Song-Ausschnitt) in Stücke und legt jedes Stück auf ein eigenes Pad. Alle Pads verwenden dieselbe Datei – es wird kein zusätzlicher Speicher belegt.")
                    .fixedSize(horizontal: false, vertical: true)
                let parts = controller.previewSlices(options)
                let a = config.settings.start, b = config.settings.end
                ZStack(alignment: .topLeading) {
                    WaveformView(peaks: regionPeaks(controller.padWaveforms[src], start: a, end: b), showsMarkers: false)
                    GeometryReader { geo in
                        ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                            let x = CGFloat((part.start - a) / max(b - a, 1e-9)) * geo.size.width
                            Rectangle().fill(Nexora.Colors.pink).frame(width: 1, height: geo.size.height).offset(x: x)
                            Text("\(options.startPad + i + 1)").font(Nexora.Fonts.value(9).bold())
                                .foregroundStyle(Nexora.Colors.pink).offset(x: x + 3, y: 2)
                        }
                    }
                }
                .frame(width: 560, height: 120)
                .background(RoundedRectangle(cornerRadius: 8).fill(Nexora.Colors.display))
                Text("\(parts.count) Slices → Pads \(options.startPad + 1)–\(min(16, options.startPad + parts.count))"
                     + (options.makePattern ? " · Pattern \(SequencerState.slotName(controller.project.sequencer.currentPattern)) wird belegt" : ""))
                    .foregroundStyle(.secondary)
                Form {
                    Picker("Modus", selection: $options.mode) {
                        Text("Nach Anschlägen (Transienten)").tag(SliceOptions.Mode.transients)
                        Text("Gleichmäßig").tag(SliceOptions.Mode.equal)
                    }
                    if options.mode == .equal {
                        Picker("Anzahl", selection: $options.count) { ForEach([2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) } }
                    } else {
                        Slider(value: $options.sensitivity, in: 0...1) { Text("Empfindlichkeit") }
                    }
                    Picker("Ab Pad", selection: $options.startPad) { ForEach(0..<16, id: \.self) { Text("Pad \($0 + 1)").tag($0) } }
                    Toggle("Pattern erzeugen (Sample = ein Pattern-Durchlauf)", isOn: $options.makePattern)
                }
                HStack {
                    Spacer()
                    Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Slicen") { if controller.slice(options) > 0 { dismiss() } }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            if !didInit { options.startPad = controller.selectedPad; didInit = true }
        }
    }

    /// Ausschnitt der Wellenform zwischen Start und Ende des Pads.
    private func regionPeaks(_ peaks: [Float], start: Double, end: Double) -> [Float] {
        guard !peaks.isEmpty else { return [] }
        let n = peaks.count
        let a = Int(start * Double(n)), b = max(a + 1, Int(end * Double(n)))
        let slice = Array(peaks[min(a, n - 1)..<min(b, n)])
        return slice.isEmpty ? peaks : slice
    }
}
