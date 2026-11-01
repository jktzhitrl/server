import SwiftUI
import NexoraCore

/// Rechter Bereich neben den Pads: Pattern-Bank, Transport, Tempo, Master.
struct TransportSectionView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                PanelSection(title: "Transport") {
                    HStack(spacing: 10) {
                        HardwareButton(title: "Play", symbol: "play.fill", isOn: controller.meters.transport == .playing,
                                       ledColor: Nexora.Colors.turquoise, width: 52, height: 34, help: "Wiedergabe starten (Leertaste)") {
                            controller.play()
                        }
                        HardwareButton(title: "Pause", symbol: "pause.fill", isOn: controller.meters.transport == .paused,
                                       width: 52, height: 34, help: "Pause – Fortsetzen an gleicher Stelle") {
                            if controller.meters.transport == .paused { controller.play() } else { controller.pause() }
                        }
                        HardwareButton(title: "Stop", symbol: "stop.fill", isOn: false, width: 52, height: 34,
                                       help: "Stopp – zurück zum Anfang") {
                            controller.stop()
                        }
                        HardwareButton(title: "Rec", symbol: "circle.fill", isOn: controller.isRecording, width: 52, height: 34,
                                       help: "Live-Aufnahme in das aktuelle Pattern (⌘R)") {
                            controller.toggleRecord()
                        }
                    }
                }
                PanelSection(title: "Pattern") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 10) {
                                ForEach(0..<4, id: \.self) { column in
                                    patternButton(row * 4 + column)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    HardwareButton(title: "Tap", symbol: "hand.tap.fill", width: 40, height: 22, help: "Tap Tempo (⌘T)") {
                        controller.tapTempo()
                    }
                    HardwareButton(title: "Click", symbol: "metronome.fill", isOn: controller.project.sequencer.metronome,
                                   ledColor: Nexora.Colors.turquoise, width: 40, height: 22, help: "Metronom (⌘K)") {
                        controller.toggleMetronome()
                    }
                    HardwareButton(title: "Copy", symbol: "doc.on.doc.fill", width: 40, height: 22, showsLED: true,
                                   help: "Aktuelles Pattern kopieren") {
                        controller.copyPattern()
                    }
                    HardwareButton(title: "Paste", symbol: "doc.on.clipboard.fill", width: 40, height: 22,
                                   help: "Kopiertes Pattern einfügen") {
                        controller.pastePattern()
                    }
                    HardwareButton(title: "Export", symbol: "square.and.arrow.up.fill", width: 40, height: 22,
                                   help: "Pattern als WAV/AIFF exportieren (⌘E)") {
                        controller.showExportSheet = true
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                PanelSection(title: "Tempo") {
                    HStack(spacing: 6) {
                        ParameterKnob(id: .tempo, title: "TEMPO", size: 44)
                        ParameterKnob(id: .swing, title: "SWING", size: 44)
                    }
                }
                PanelSection(title: "Master") {
                    HStack(alignment: .bottom, spacing: 10) {
                        ParameterKnob(id: .masterVolume, title: "MASTER", size: 44)
                        HStack(spacing: 3) {
                            LEDMeter(level: controller.meters.peakLeft)
                            LEDMeter(level: controller.meters.peakRight)
                        }
                        .padding(.bottom, 22)
                        .help("Ausgangspegel links/rechts")
                    }
                }
                HStack(spacing: 6) {
                    SelectorButton(caption: "Rec Q", value: controller.project.sequencer.quantize.shortName, width: 44,
                                   help: "Quantisierung bei der Live-Aufnahme") {
                        let all = QuantizeMode.allCases
                        let i = all.firstIndex(of: controller.project.sequencer.quantize) ?? 0
                        controller.setQuantize(all[(i + 1) % all.count])
                    }
                    SelectorButton(caption: "Poly", value: "\(controller.project.engine.polyphony)", width: 36,
                                   help: "Polyphonie (maximale Stimmen) – in den Einstellungen anpassbar") {
                        let options = [8, 16, 32, 48, 64]
                        let next = options.first { $0 > controller.project.engine.polyphony } ?? options[0]
                        controller.updateEngineSettings { $0.polyphony = next }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func patternButton(_ slot: Int) -> some View {
        let current = controller.project.sequencer.currentPattern == slot
        let queued = controller.meters.queuedPattern == slot
        let hasContent = !controller.project.sequencer.patterns[slot].isEmpty
        return VStack(spacing: 4) {
            LEDView(isOn: current || queued, color: queued ? Nexora.Colors.turquoise : Nexora.Colors.pink, size: 5)
            Button {
                controller.selectPattern(slot)
            } label: {
                Text(SequencerState.slotName(slot))
                    .font(Nexora.Fonts.label(11))
                    .foregroundStyle(hasContent ? Nexora.Colors.labelLight : Nexora.Colors.labelMuted.opacity(0.6))
                    .frame(width: 52, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [Nexora.Colors.buttonTop, Nexora.Colors.buttonBottom], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(current ? Nexora.Colors.pink.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
            }
            .buttonStyle(PressableButtonStyle())
            .help("Pattern \(SequencerState.slotName(slot)) (⌘\(slot + 1))\(hasContent ? "" : " – leer")")
        }
    }
}
