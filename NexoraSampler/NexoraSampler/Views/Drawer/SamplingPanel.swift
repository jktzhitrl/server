import SwiftUI
import CoreAudio
import NexoraCore

/// Aufnahme neuer Samples (Mikrofon / Line-In / Resampling) und Pattern-Resampling.
struct SamplingPanel: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        @Bindable var c = controller
        HStack(alignment: .top, spacing: 18) {
            DrawerSection(title: "Aufnahme (Sampling)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Quelle").foregroundStyle(Nexora.Colors.labelMuted)
                        Picker("", selection: $c.sampling.source) {
                            Text("Mikrofon / Line-In").tag(SamplingState.Source.input)
                            Text("Resampling (eigener Ausgang)").tag(SamplingState.Source.output)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 360)
                        .disabled(controller.sampling.isActive)
                    }
                    HStack(spacing: 8) {
                        Picker("Eingang", selection: $c.sampling.deviceID) {
                            Text("Standard-Eingang").tag(AudioDeviceID?.none)
                            ForEach(controller.inputDevices) { d in Text(d.name).tag(Optional(d.id)) }
                        }
                        .frame(width: 300)
                        .disabled(controller.sampling.source != .input || controller.sampling.isActive)
                        Button("Geräte suchen") { controller.refreshInputDevices() }
                    }
                    HStack(spacing: 8) {
                        Picker("Start", selection: $c.sampling.thresholdDb) {
                            Text("Sofort").tag(Double?.none)
                            ForEach([-50.0, -40, -30, -20], id: \.self) { db in Text("ab \(Int(db)) dB").tag(Optional(db)) }
                        }
                        .frame(width: 140)
                        Picker("Länge", selection: $c.sampling.maxSeconds) {
                            ForEach([10.0, 30, 60, 300, 600], id: \.self) { v in
                                Text("max. " + (v < 60 ? "\(Int(v)) s" : "\(Int(v) / 60) min")).tag(v)
                            }
                        }
                        .frame(width: 150)
                        Picker("Ziel", selection: $c.sampling.targetPad) {
                            ForEach(0..<16, id: \.self) { i in
                                Text("Pad \(i + 1) · \(controller.padSamples[i] == nil ? "leer" : controller.project.pads[i].name)").tag(i)
                            }
                        }
                        .frame(width: 200)
                    }
                    HStack(spacing: 14) {
                        Toggle("Mithören", isOn: $c.sampling.monitor).toggleStyle(.checkbox)
                            .help("Eingang über die Lautsprecher hören (Vorsicht vor Rückkopplung)")
                        Toggle("Wiedergabe mitstarten", isOn: $c.sampling.startPlayback).toggleStyle(.checkbox)
                            .help("Beim Resampling startet der Sequencer mit der Aufnahme und stoppt mit ihr")
                    }
                    HStack(spacing: 10) {
                        Button(controller.sampling.isActive ? "■ Stopp" : "● Aufnahme starten") {
                            controller.sampling.isActive ? controller.stopSampling() : controller.startSampling()
                        }
                        LevelBar(level: controller.sampling.level).frame(width: 180, height: 10)
                        Text(statusText).foregroundStyle(Nexora.Colors.labelMuted)
                    }
                    Text("Mikrofon / Line-In nimmt über das gewählte Audiogerät auf. Resampling nimmt alles auf, was NEXORA gerade spielt – inklusive XY-Pad-Bewegungen und Effekten. Die Aufnahme landet auf dem Ziel-Pad und wird beim Speichern ins Projekt kopiert.")
                        .foregroundStyle(Nexora.Colors.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 640, alignment: .topLeading)
            DrawerSection(title: "Pattern resamplen") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rendert das aktuelle Pattern einmal (ohne Ausklang, nahtlos loopbar) mit allen Effekten auf das Ziel-Pad – z. B. um einen Beat als Loop weiterzuverarbeiten oder Pads freizumachen.")
                        .foregroundStyle(Nexora.Colors.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(controller.isResampling ? "Rendert …"
                           : "Pattern \(SequencerState.slotName(controller.project.sequencer.currentPattern)) → Pad \(controller.sampling.targetPad + 1)") {
                        controller.resamplePattern()
                    }
                    .disabled(controller.isResampling)
                }
            }
            .frame(width: 380, alignment: .topLeading)
        }
        .font(.system(size: 11))
        .onAppear { controller.refreshInputDevices() }
    }

    private var statusText: String {
        switch controller.sampling.phase {
        case .idle: return "Bereit"
        case .armed: return "Wartet auf Signal …"
        case .recording: return String(format: "Aufnahme läuft · %.1f s", controller.sampling.seconds)
        }
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        let db = level > 0 ? 20 * log10(Double(level)) : -90
        let fraction = max(0, min(1, (db + 60) / 60))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Nexora.Colors.panelDeep)
                RoundedRectangle(cornerRadius: 5).fill(db > -1 ? Nexora.Colors.ledRed : Nexora.Colors.turquoise)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }
}
