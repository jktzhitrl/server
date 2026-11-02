import SwiftUI
import NexoraCore

/// Das Gehäuse des Instruments im Groovebox-Layout:
/// links Lautstärke, LCD, Transport und Touchpad – rechts Daten-Regler, Navigation,
/// fünf Regler-Sektionen, Funktionstasten und 16 Pads in zwei Reihen.
struct InstrumentBodyView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            BodyShell()
            HStack(alignment: .top, spacing: 30) {
                LeftColumnView()
                    .frame(width: 290)
                VStack(alignment: .leading, spacing: 0) {
                    BrandHeaderView()
                        .frame(height: 74)
                    ControlSectionsView()
                        .frame(height: 290)
                    ButtonRowView()
                        .frame(height: 50)
                        .padding(.top, 10)
                    PadGridView()
                        .padding(.top, 22)
                }
                .frame(width: 944)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
        }
        .frame(width: Nexora.Metrics.designWidth, height: Nexora.Metrics.bodyHeight)
    }
}

/// Metallisch lackiertes Gehäuse mit Fase.
private struct BodyShell: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Nexora.Metrics.corner, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.bodyTop, Nexora.Colors.bodyBottom], startPoint: .top, endPoint: .bottom))
            // Metallischer Glanz
            RoundedRectangle(cornerRadius: Nexora.Metrics.corner, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: Color.white.opacity(0.10), location: 0),
                    .init(color: Color.white.opacity(0.0), location: 0.35),
                    .init(color: Color.black.opacity(0.0), location: 0.7),
                    .init(color: Color.black.opacity(0.12), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            // Innere Kante
            RoundedRectangle(cornerRadius: Nexora.Metrics.corner - 6, style: .continuous)
                .strokeBorder(Nexora.Colors.bodyHighlight.opacity(0.25), lineWidth: 1)
                .padding(8)
            RoundedRectangle(cornerRadius: Nexora.Metrics.corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Nexora.Colors.bodyHighlight.opacity(0.8), Nexora.Colors.bodyEdge],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
        }
        .shadow(color: .black.opacity(0.6), radius: 26, x: 0, y: 16)
    }
}

/// Schriftzug und Status-LEDs oben rechts.
struct BrandHeaderView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                LEDView(isOn: controller.meters.midiActivity, color: Nexora.Colors.turquoise, size: 6)
                PanelLabel(text: "MIDI", size: 8)
                LEDView(isOn: controller.isRecording, color: Nexora.Colors.ledRed, size: 6)
                PanelLabel(text: "REC", size: 8)
                LEDView(isOn: controller.meters.transport == .playing, color: Nexora.Colors.blueGlow, size: 6)
                PanelLabel(text: "RUN", size: 8)
            }
            .padding(.top, 8)
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("nexora")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                    Text("sampler")
                        .font(.system(size: 38, weight: .light, design: .rounded))
                }
                .foregroundStyle(Nexora.Colors.bodyLabel)
                Text("PERFORMANCE SAMPLER · 16 PADS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Nexora.Colors.bodyLabelMuted)
            }
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1)
        }
    }
}
