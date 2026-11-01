import SwiftUI
import NexoraCore

/// Hellblaues LCD oben links: Sample, Kit/Preset, BPM, Sample-Infos, Modus und Schrittanzeige.
struct LCDDisplayView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        let pad = controller.selectedPad
        let config = controller.project.pads[pad]
        let sample = controller.padSamples[pad]
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Nexora.Colors.display)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.lcdBackground, Nexora.Colors.lcdBackgroundDark], startPoint: .top, endPoint: .bottom))
                .overlay(LCDPixelGrid().opacity(0.07))
                .overlay(
                    VStack(alignment: .leading, spacing: 3) {
                        topRow
                        Rectangle().fill(Nexora.Colors.lcdInk.opacity(0.35)).frame(height: 1)
                        mainArea(config: config, sample: sample, pad: pad)
                        WaveformView(peaks: controller.padWaveforms[pad], start: config.settings.start, end: config.settings.end,
                                     color: Nexora.Colors.lcdInk, dimColor: Nexora.Colors.lcdInkDim,
                                     markerColor: Nexora.Colors.lcdInk, reverse: config.settings.reverse)
                            .frame(height: 24)
                        stepRow
                        bottomRow(sample: sample)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                )
                .padding(6)
                .shadow(color: Nexora.Colors.lcdBackground.opacity(0.35), radius: 6)
        }
        .help("Display: zeigt ausgewähltes Pad, Kit, Tempo, Sample-Informationen und Modus")
    }

    private var topRow: some View {
        HStack(spacing: 6) {
            Text(modeName)
                .font(Nexora.Fonts.lcd(10))
            Spacer()
            Text("PTN \(SequencerState.slotName(controller.project.sequencer.currentPattern))"
                 + (controller.meters.queuedPattern >= 0 ? "→\(SequencerState.slotName(controller.meters.queuedPattern))" : ""))
                .font(Nexora.Fonts.lcd(10))
            Text(String(format: "%.1f BPM", controller.project.bpm))
                .font(Nexora.Fonts.lcd(10))
        }
        .foregroundStyle(Nexora.Colors.lcdInk)
    }

    @ViewBuilder
    private func mainArea(config: PadConfig, sample: SampleBuffer?, pad: Int) -> some View {
        if let message = controller.lcdMessage {
            VStack(alignment: .leading, spacing: 0) {
                Text(message.title)
                    .font(Nexora.Fonts.lcd(10))
                    .lineLimit(1)
                Text(message.value.isEmpty ? " " : message.value)
                    .font(Nexora.Fonts.lcd(17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Nexora.Colors.lcdInk)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("KIT \(controller.project.kitName.uppercased())")
                    .font(Nexora.Fonts.lcd(10))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(format: "%02d", pad + 1))
                        .font(Nexora.Fonts.lcd(17))
                        .padding(.horizontal, 3)
                        .background(Nexora.Colors.lcdInk)
                        .foregroundStyle(Nexora.Colors.lcdBackground)
                    Text(sample == nil ? "— NO SAMPLE —" : config.name)
                        .font(Nexora.Fonts.lcd(17))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Nexora.Colors.lcdInk)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stepRow: some View {
        let pattern = controller.project.currentPattern
        let track = controller.selectedPad
        let playing = controller.meters.transport != .stopped
        return HStack(spacing: 2) {
            ForEach(0..<SequencerPattern.maxSteps, id: \.self) { step in
                let active = pattern[track, step].active
                let current = playing && controller.meters.currentStep == step
                RoundedRectangle(cornerRadius: 1)
                    .fill(Nexora.Colors.lcdInk.opacity(step >= pattern.length ? 0.06 : (current ? 1 : (active ? 0.65 : 0.15))))
                    .frame(height: 5)
                    .overlay(current && active ? RoundedRectangle(cornerRadius: 1).stroke(Nexora.Colors.lcdBackground, lineWidth: 1) : nil)
            }
        }
    }

    private func bottomRow(sample: SampleBuffer?) -> some View {
        HStack(spacing: 8) {
            if let sample {
                Text(String(format: "%.1fk %@ %.2fs", sample.sampleRate / 1000, sample.isStereo ? "ST" : "MO", sample.duration))
            } else {
                Text("DROP AUDIO ON A PAD")
            }
            Spacer()
            Text("V\(controller.meters.activeVoices)/\(controller.project.engine.polyphony)")
            Text("CPU \(Int(controller.meters.load * 100))%")
        }
        .font(Nexora.Fonts.lcd(8.5))
        .foregroundStyle(Nexora.Colors.lcdInk.opacity(0.85))
    }

    private var modeName: String {
        if controller.midiLearnActive { return "MIDI LEARN" }
        if controller.isRecording { return "● REC \(controller.project.sequencer.quantize.shortName)" }
        switch controller.padMode {
        case .play: return controller.drawer.map { $0.title } ?? "PAD PLAY"
        case .step: return "STEP EDIT T\(String(format: "%02d", controller.selectedPad + 1))"
        }
    }
}

/// Feines Pixelraster für den LCD-Look.
private struct LCDPixelGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.width, by: 3).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: 3).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.black), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
