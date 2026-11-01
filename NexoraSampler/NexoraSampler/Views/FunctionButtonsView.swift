import SwiftUI
import NexoraCore

/// Die schwarzen Funktionstasten unter dem Display.
struct FunctionButtonsView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HardwareButton(title: "Pad", isOn: controller.padMode == .play, help: "Pads spielen Samples") {
                    controller.padMode = .play
                    controller.showLCD("MODE", "PAD PLAY", seconds: 1)
                }
                HardwareButton(title: "Step", isOn: controller.padMode == .step, ledColor: Nexora.Colors.turquoise,
                               help: "Step-Modus: Die Pads schalten die 16 Schritte der ausgewählten Spur") {
                    controller.padMode = controller.padMode == .step ? .play : .step
                    controller.showLCD("MODE", controller.padMode == .step ? "STEP EDIT" : "PAD PLAY", seconds: 1)
                }
                drawerButton("Edit", .editor, help: "Pad-Editor: Sample, Hüllkurve, Filter, LFO, Effekte je Pad")
                drawerButton("Browse", .browser, help: "Sample-Browser und Bibliotheken")
            }
            HStack(spacing: 12) {
                drawerButton("Seq", .sequencer, help: "Step-Sequencer mit 16 Spuren × 16 Schritten")
                drawerButton("FX", .effects, help: "Master-Effekte: Delay, Reverb, Kompressor, Modulation")
                drawerButton("Kit", .kits, help: "Drum-Kits, Effekt- und Pattern-Presets")
                HardwareButton(title: "Learn", isOn: controller.midiLearnActive, ledColor: Nexora.Colors.turquoise,
                               help: "MIDI-Learn: Regler berühren, dann Controller am MIDI-Gerät bewegen") {
                    controller.toggleMIDILearn()
                }
            }
        }
    }

    private func drawerButton(_ title: String, _ panel: DrawerPanel, help: String) -> some View {
        HardwareButton(title: title, isOn: controller.drawer == panel, help: help) {
            controller.drawer = controller.drawer == panel ? nil : panel
        }
    }
}
