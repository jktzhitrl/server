import SwiftUI

/// Kleine LED mit Leuchtschein.
struct LEDView: View {
    var isOn: Bool
    var color: Color = Nexora.Colors.pink
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(isOn ? color : Nexora.Colors.ledOff)
            .frame(width: size, height: size)
            .overlay(Circle().fill(Color.white.opacity(isOn ? 0.55 : 0.08)).frame(width: size * 0.35, height: size * 0.35).offset(x: -size * 0.15, y: -size * 0.15))
            .shadow(color: isOn ? color.opacity(0.9) : .clear, radius: isOn ? 4 : 0)
            .animation(.easeOut(duration: 0.12), value: isOn)
            .accessibilityHidden(true)
    }
}

/// Pegelanzeige aus LED-Segmenten.
struct LEDMeter: View {
    var level: Float
    var segments = 12
    var vertical = true

    var body: some View {
        let lit = Int((DSPLevel.toMeter(level) * Double(segments)).rounded())
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(0..<segments, id: \.self) { i in
                let index = vertical ? segments - 1 - i : i
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(for: index).opacity(index < lit ? 1 : 0.16))
                    .frame(width: vertical ? 8 : 5, height: vertical ? 4 : 8)
                    .shadow(color: index < lit ? color(for: index).opacity(0.7) : .clear, radius: 2)
            }
        }
    }

    private func color(for index: Int) -> Color {
        if index >= segments - 2 { return Nexora.Colors.pink }
        if index >= segments - 4 { return Color(hex: 0xFFD166) }
        return Nexora.Colors.turquoise
    }
}

enum DSPLevel {
    /// Lineare Amplitude → 0 ... 1 auf einer −48-dB-Skala.
    static func toMeter(_ level: Float) -> Double {
        guard level > 0.000_01 else { return 0 }
        let db = 20 * log10(Double(level))
        return min(max((db + 48) / 48, 0), 1)
    }
}
