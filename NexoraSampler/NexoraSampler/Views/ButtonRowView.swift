import SwiftUI
import NexoraCore

/// Funktionstasten über den Pads und Pattern-Tasten (Bank A–D / E–H).
struct ButtonRowView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        let seq = controller.project.sequencer
        let pad = controller.selectedPad
        HStack(alignment: .center, spacing: 8) {
            FaceButton(title: "◀ Pad", width: 74, height: 28, help: "Vorheriges Pad auswählen") { controller.selectPad((pad + 15) % 16) }
            FaceButton(title: "Pad ▶", width: 74, height: 28, help: "Nächstes Pad auswählen") { controller.selectPad((pad + 1) % 16) }
            FaceButton(title: "Pad Mute", isLit: seq.trackMutes[pad], width: 74, height: 28,
                       help: "Spur des ausgewählten Pads im Sequencer stummschalten") { controller.toggleMute(pad) }
            FaceButton(title: "Pad Erase", width: 74, height: 28, help: "Spur des ausgewählten Pads im Pattern löschen") {
                controller.clearTrack(pad)
                controller.showLCD(String(format: "PAD %02d", pad + 1), "TRACK ERASED")
            }
            FaceButton(title: "Trigger", isLit: controller.padMode == .play, width: 74, height: 28,
                       help: "Pads spielen die Samples") { controller.setPadMode(.play) }
            FaceButton(title: "Sequencer", isLit: controller.padMode == .step, width: 74, height: 28,
                       help: "Pads = 16 Schritte der ausgewählten Spur") { controller.setPadMode(.step) }
            FaceButton(title: "Keyboard", isLit: controller.padMode == .keyboard, width: 74, height: 28,
                       help: "Pads spielen das ausgewählte Sample chromatisch (untere Reihe weiße, obere Reihe schwarze Tasten)") {
                controller.setPadMode(.keyboard)
            }
            FaceButton(title: "Seq Edit", isLit: controller.drawer == .sequencer, width: 74, height: 28,
                       help: "Sequencer-Raster 16 × 16") { controller.toggleDrawer(.sequencer) }
            FaceButton(title: "MIDI", isLit: controller.drawer == .midi, width: 74, height: 28,
                       help: "MIDI-Geräte, Noten und CC-Zuordnungen") { controller.toggleDrawer(.midi) }
            FaceButton(title: "Bank \(controller.patternBank == 0 ? "A–D" : "E–H")", width: 74, height: 28,
                       help: "Pattern-Bank umschalten") { controller.patternBank = 1 - controller.patternBank }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    patternButton(controller.patternBank * 4 + i)
                }
            }
        }
    }

    private func patternButton(_ slot: Int) -> some View {
        let current = controller.project.sequencer.currentPattern == slot
        let queued = controller.meters.queuedPattern == slot
        let hasContent = !controller.project.sequencer.patterns[slot].isEmpty
        return FaceButton(title: SequencerState.slotName(slot), isLit: current || queued,
                          litColor: queued ? Nexora.Colors.turquoise : Nexora.Colors.violetGlow,
                          fillWhenLit: current, width: 27, height: 44, fontSize: 12,
                          help: "Pattern \(SequencerState.slotName(slot)) (⌘\(slot + 1))\(hasContent ? "" : " – leer")") {
            controller.selectPattern(slot)
        }
        .opacity(hasContent || current ? 1 : 0.7)
    }
}
