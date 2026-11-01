import SwiftUI

/// Einheitliches Designsystem des NEXORA Samplers: Farben, Schriften, Maße.
enum Nexora {
    enum Colors {
        // Gehäuse (Pastell-Lila) und Paneele (Dunkelviolett)
        static let bodyTop = Color(hex: 0xD6C6F0)
        static let bodyBottom = Color(hex: 0xAE98DD)
        static let bodyEdge = Color(hex: 0x8C74C4)
        static let panel = Color(hex: 0x3B2D5E)
        static let panelDeep = Color(hex: 0x261C40)
        static let panelLine = Color(hex: 0x5B4888)

        // Displays
        static let display = Color(hex: 0x0A090F)
        static let lcdBackground = Color(hex: 0xA9DEF3)
        static let lcdBackgroundDark = Color(hex: 0x86C9E6)
        static let lcdInk = Color(hex: 0x0F2C3B)
        static let lcdInkDim = Color(hex: 0x0F2C3B).opacity(0.18)

        // Bedienelemente
        static let knobHighlight = Color(hex: 0xE4F6FF)
        static let knobBlue = Color(hex: 0xA9DDF5)
        static let knobShadow = Color(hex: 0x6FB2D6)
        static let knobMark = Color(hex: 0x1D2440)
        static let buttonTop = Color(hex: 0x2B2635)
        static let buttonBottom = Color(hex: 0x15121C)

        // Akzente
        static let turquoise = Color(hex: 0x3EE6D2)
        static let pink = Color(hex: 0xFF4FA8)
        static let ledOff = Color(hex: 0x4A2440)
        static let blueGlow = Color(hex: 0x57C8FF)

        // Pads
        static let padIdle = Color(hex: 0x2C2244)
        static let padIdleTop = Color(hex: 0x3A2E58)
        static let padEmpty = Color(hex: 0x231B36)

        // Text
        static let labelDark = Color(hex: 0x2D2050)
        static let labelLight = Color(hex: 0xEDE6FF)
        static let labelMuted = Color(hex: 0xB9AEDA)
    }

    enum Fonts {
        static func label(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .bold, design: .rounded) }
        static func lcd(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
        static func brand(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
        static func value(_ size: CGFloat = 8.5) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
    }

    enum Metrics {
        static let designWidth: CGFloat = 1320
        static let bodyHeight: CGFloat = 660
        static let drawerHeight: CGFloat = 330
        static let corner: CGFloat = 18
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Beschriftung auf dem Gehäuse (dunkle Kapitälchen).
struct PanelLabel: View {
    let text: String
    var color: Color = Nexora.Colors.labelDark
    var size: CGFloat = 9

    var body: some View {
        Text(text.uppercased())
            .font(Nexora.Fonts.label(size))
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Abschnitt mit Überschrift und feiner Trennlinie, wie auf Hardware-Frontplatten.
struct PanelSection<Content: View>: View {
    let title: String
    var color: Color = Nexora.Colors.labelDark
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PanelLabel(text: title, color: color, size: 8.5)
                Rectangle().fill(color.opacity(0.35)).frame(height: 1)
            }
            content
        }
    }
}

/// Dunkles, eingelassenes Paneel (z. B. für den Drawer).
struct InsetPanel<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Nexora.Colors.panelDeep)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Nexora.Colors.panelLine.opacity(0.7), lineWidth: 1))
            )
    }
}
