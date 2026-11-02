import SwiftUI

/// Farbschema des Gehäuses.
enum NexoraTheme: String, CaseIterable, Identifiable {
    /// Metallisch-rotes Gehäuse, graue Metallregler, graublaues LCD
    case crimson
    /// Pastell-lila Gehäuse, hellblaue Regler, hellblaues LCD
    case lilac

    var id: String { rawValue }
    var title: String { self == .crimson ? "Crimson (Metallic-Rot)" : "Lilac (Pastell-Lila)" }
    static let storageKey = "ui.theme"
}

/// Einheitliches Designsystem des NEXORA Samplers: Farben, Schriften, Maße.
/// Die Farben hängen vom gewählten Thema ab (`Nexora.theme`).
enum Nexora {
    static var theme: NexoraTheme = .crimson
    private static var crimson: Bool { theme == .crimson }

    enum Colors {
        // Gehäuse
        static var bodyTop: Color { crimson ? Color(hex: 0x9A3346) : Color(hex: 0xD6C6F0) }
        static var bodyBottom: Color { crimson ? Color(hex: 0x7A2234) : Color(hex: 0xAE98DD) }
        static var bodyEdge: Color { crimson ? Color(hex: 0x5A1424) : Color(hex: 0x8C74C4) }
        static var bodyHighlight: Color { crimson ? Color(hex: 0xC4687A) : Color.white }
        /// Beschriftung auf dem Gehäuse
        static var bodyLabel: Color { crimson ? Color(hex: 0xF4E6E9) : Color(hex: 0x2D2050) }
        static var bodyLabelMuted: Color { crimson ? Color(hex: 0xE3C3CA) : Color(hex: 0x4A3A75) }

        // Dunkle Flächen (Drawer, Pad-Feld)
        static var panel: Color { crimson ? Color(hex: 0x2E2226) : Color(hex: 0x3B2D5E) }
        static var panelDeep: Color { crimson ? Color(hex: 0x1C1416) : Color(hex: 0x261C40) }
        static var panelLine: Color { crimson ? Color(hex: 0x553840) : Color(hex: 0x5B4888) }

        // Displays
        static let display = Color(hex: 0x0A090F)
        static var lcdBackground: Color { crimson ? Color(hex: 0xC3CEDF) : Color(hex: 0xA9DEF3) }
        static var lcdBackgroundDark: Color { crimson ? Color(hex: 0xA3B2C9) : Color(hex: 0x86C9E6) }
        static var lcdInk: Color { crimson ? Color(hex: 0x1B2233) : Color(hex: 0x0F2C3B) }
        static var lcdInkDim: Color { lcdInk.opacity(0.18) }
        static var lcdBand: Color { crimson ? Color(hex: 0x2B3654) : Color(hex: 0x123647) }
        static var lcdBandText: Color { crimson ? Color(hex: 0xD3DDEE) : Color(hex: 0xBDEBFA) }
        static var lcdFrame: Color { crimson ? Color(hex: 0x6B1A2B) : Color(hex: 0x0A090F) }

        // Drehregler
        static var knobHighlight: Color { crimson ? Color(hex: 0xEDEEF1) : Color(hex: 0xE4F6FF) }
        static var knobBlue: Color { crimson ? Color(hex: 0xA8AAB1) : Color(hex: 0xA9DDF5) }
        static var knobShadow: Color { crimson ? Color(hex: 0x65676E) : Color(hex: 0x6FB2D6) }
        static var knobSkirt: Color { crimson ? Color(hex: 0x2A2528) : Color(hex: 0x5B4888) }
        static let knobMark = Color(hex: 0x1D2028)
        static var knobRing: Color { crimson ? Color(hex: 0xF4E6E9).opacity(0.55) : Color(hex: 0x3EE6D2) }
        /// Großer Daten-/Tempo-Regler
        static var jogTop: Color { crimson ? Color(hex: 0xB2384E) : Color(hex: 0xC9B6F2) }
        static var jogBottom: Color { crimson ? Color(hex: 0x6A1626) : Color(hex: 0x7E62C2) }

        // Tasten
        static let buttonTop = Color(hex: 0x34303A)
        static let buttonBottom = Color(hex: 0x16141A)
        static let buttonText = Color(hex: 0xE8E4EE)

        // Akzente
        static let turquoise = Color(hex: 0x3EE6D2)
        static let pink = Color(hex: 0xFF4FA8)
        static let ledRed = Color(hex: 0xFF2E45)
        static let ledOff = Color(hex: 0x4A2440)
        static let blueGlow = Color(hex: 0x57C8FF)
        static let playBlue = Color(hex: 0x3D6BFF)
        static let violetGlow = Color(hex: 0xB45CFF)

        // Pads
        static let padIdle = Color(hex: 0x1F1C22)
        static let padIdleTop = Color(hex: 0x2C2830)
        static let padEmpty = Color(hex: 0x19171B)

        // Text auf dunklem Grund
        static let labelLight = Color(hex: 0xEDE6FF)
        static let labelMuted = Color(hex: 0xB9AEC2)
        /// Abwärtskompatibel: Beschriftung auf dem Gehäuse
        static var labelDark: Color { bodyLabel }
    }

    enum Fonts {
        static func label(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .bold, design: .rounded) }
        static func lcd(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
        static func brand(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
        static func value(_ size: CGFloat = 8.5) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
        static func section(_ size: CGFloat = 21) -> Font { .system(size: size, weight: .medium, design: .default) }
        static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .medium, design: .default) }
    }

    enum Metrics {
        static let designWidth: CGFloat = 1320
        static let bodyHeight: CGFloat = 742
        static let drawerHeight: CGFloat = 330
        static let corner: CGFloat = 22
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
    var color: Color = Nexora.Colors.bodyLabel
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
    var color: Color = Nexora.Colors.bodyLabel
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
