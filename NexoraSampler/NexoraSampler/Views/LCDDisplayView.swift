import SwiftUI
import NexoraCore

/// Hintergrundbeleuchtetes LCD: oben Tempo und Pattern, in der Mitte ein invertiertes Band
/// mit Pad-Nummer und Name (bzw. dem gerade bedienten Parameter), unten Sample-Infos.
struct LCDDisplayView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        let pad = controller.selectedPad
        let config = controller.project.pads[pad]
        let sample = controller.padSamples[pad]
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.lcdFrame, Nexora.Colors.lcdFrame.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.lcdBackground, Nexora.Colors.lcdBackgroundDark], startPoint: .top, endPoint: .bottom))
                .overlay(LCDPixelGrid().opacity(0.06))
                .overlay(
                    VStack(spacing: 4) {
                        topRow
                        band(config: config, sample: sample, pad: pad)
                        WaveformView(peaks: controller.padWaveforms[pad], start: config.settings.start, end: config.settings.end,
                                     color: Nexora.Colors.lcdInk.opacity(0.85), dimColor: Nexora.Colors.lcdInkDim,
                                     markerColor: Nexora.Colors.lcdInk, reverse: config.settings.reverse)
                            .frame(height: 18)
                        stepRow
                        bottomRow(config: config, sample: sample, pad: pad)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                )
                .padding(9)
        }
        .help("Display: Tempo, Pattern, ausgewähltes Pad, Sample-Informationen und Modus")
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            Text(modeName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f", controller.project.bpm))
                .font(Nexora.Fonts.lcd(13))
            HStack(spacing: 3) {
                Text("PTN \(SequencerState.slotName(controller.project.sequencer.currentPattern))"
                     + (controller.meters.queuedPattern >= 0 ? "›\(SequencerState.slotName(controller.meters.queuedPattern))" : ""))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(Nexora.Fonts.lcd(9.5))
        .foregroundStyle(Nexora.Colors.lcdInk)
    }

    private func band(config: PadConfig, sample: SampleBuffer?, pad: Int) -> some View {
        let message = controller.lcdMessage
        return VStack(alignment: .leading, spacing: 0) {
            if let message {
                Text(message.title).font(Nexora.Fonts.lcd(9.5)).lineLimit(1)
                Text(message.value.isEmpty ? " " : message.value)
                    .font(Nexora.Fonts.lcd(19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            } else {
                Text(String(format: "%03d", pad + 1)).font(Nexora.Fonts.lcd(11)).lineLimit(1)
                Text(sample == nil ? "— empty —" : config.name.capitalized)
                    .font(Nexora.Fonts.lcd(21))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .foregroundStyle(Nexora.Colors.lcdBandText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 50)
        .background(Nexora.Colors.lcdBand)
    }

    private var stepRow: some View {
        let pattern = controller.project.currentPattern
        let track = controller.selectedPad
        let playing = controller.meters.transport != .stopped
        let offset = controller.stepPage * SequencerPattern.stepsPerPage
        return HStack(spacing: 2) {
            ForEach(offset..<(offset + SequencerPattern.stepsPerPage), id: \.self) { step in
                let active = pattern[track, step].active
                let current = playing && controller.meters.currentStep == step
                Rectangle()
                    .fill(Nexora.Colors.lcdInk.opacity(step >= pattern.length ? 0.06 : (current ? 1 : (active ? 0.6 : 0.15))))
                    .frame(height: 4)
            }
        }
    }

    private func bottomRow(config: PadConfig, sample: SampleBuffer?, pad: Int) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "Pad:%02d %@", pad + 1, config.settings.playMode.shortName)
                 + (controller.pageCount > 1 ? " P\(controller.stepPage + 1)/\(controller.pageCount)" : "")
                 + (controller.project.sequencer.songMode && controller.meters.songIndex >= 0
                    ? " SONG \(controller.meters.songIndex + 1)/\(controller.project.patternChain.count)" : ""))
            if let sample {
                Text(String(format: "%.1fk %@ %.2fs", sample.sampleRate / 1000, sample.isStereo ? "ST" : "MO", sample.duration))
            }
            Spacer()
            Text("V\(controller.meters.activeVoices)")
        }
        .font(Nexora.Fonts.lcd(9))
        .foregroundStyle(Nexora.Colors.lcdInk)
        .lineLimit(1)
    }

    private var modeName: String {
        if controller.factoryInstallProgress != nil { return "SETUP" }
        if controller.midiLearnActive { return "LEARN" }
        if controller.isRecording { return "● REC" }
        switch controller.padMode {
        case .play: return controller.drawer.map { String($0.title.prefix(8)) } ?? "TRIGGER"
        case .step: return "SEQ"
        case .keyboard: return "KEYS"
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
