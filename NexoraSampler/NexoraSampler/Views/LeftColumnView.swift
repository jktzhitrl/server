import SwiftUI
import NexoraCore

/// Linke Spalte: Lautstärke/Swing, LCD, Transport, Funktionstasten, Touchpad.
struct LeftColumnView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                ParameterKnob(id: .masterVolume, title: "Volume", size: 36, showsValue: false)
                ParameterKnob(id: .swing, title: "Swing", size: 36, showsValue: false)
                Spacer()
                HStack(spacing: 3) {
                    LEDMeter(level: controller.meters.peakLeft, segments: 10)
                    LEDMeter(level: controller.meters.peakRight, segments: 10)
                }
                .padding(.top, 6)
                .help("Ausgangspegel links/rechts")
            }
            .frame(height: 72)

            LCDDisplayView()
                .frame(width: 290, height: 156)

            HStack(spacing: 10) {
                FaceButton(title: "", symbol: "circle.fill", isLit: controller.isRecording, litColor: Nexora.Colors.ledRed,
                           width: 64, height: 50, help: "Live-Aufnahme (⌘R)") { controller.toggleRecord() }
                FaceButton(title: "", symbol: "stop.fill", width: 64, height: 50, help: "Stopp – zurück zum Anfang") { controller.stop() }
                FaceButton(title: "", symbol: "playpause.fill", isLit: controller.meters.transport == .playing,
                           litColor: Nexora.Colors.playBlue, fillWhenLit: true, width: 64, height: 50,
                           help: "Play/Pause (Leertaste = Play/Stop)") {
                    if controller.meters.transport == .playing { controller.pause() } else { controller.play() }
                }
                FaceButton(title: "Tap", width: 64, height: 50, fontSize: 15, help: "Tap-Tempo (⌘T)") { controller.tapTempo() }
            }

            HStack(spacing: 10) {
                FaceButton(title: "Click", isLit: controller.project.sequencer.metronome, width: 64, height: 26,
                           help: "Metronom (⌘K)") { controller.toggleMetronome() }
                FaceButton(title: "XY Latch", isLit: controller.xyLatch, width: 64, height: 26,
                           help: "Touchpad-Werte nach dem Loslassen halten") { controller.xyLatch.toggle() }
                FaceButton(title: "Master Fx", isLit: controller.drawer == .effects, width: 64, height: 26,
                           help: "Master-Effekte: Delay, Hall, EQ, Kompressor, Modulation") { controller.toggleDrawer(.effects) }
                FaceButton(title: "Learn", isLit: controller.midiLearnActive, litColor: Nexora.Colors.turquoise, width: 64, height: 26,
                           help: "MIDI-Learn: Regler anklicken, dann Controller am MIDI-Gerät bewegen") { controller.toggleMIDILearn() }
            }

            XYPadView()
                .frame(width: 290, height: 290)
        }
    }
}
