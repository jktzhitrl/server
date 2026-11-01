import SwiftUI

/// Gedrückt-Animation für Hardware-Tasten.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Dunkle rechteckige Funktionstaste mit LED und Beschriftung.
struct HardwareButton: View {
    let title: String
    var symbol: String?
    var isOn: Bool = false
    var ledColor: Color = Nexora.Colors.pink
    var width: CGFloat = 64
    var height: CGFloat = 24
    var showsLED = true
    var labelColor: Color = Nexora.Colors.labelDark
    var help: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if showsLED { LEDView(isOn: isOn, color: ledColor, size: 5) }
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Nexora.Colors.buttonTop, Nexora.Colors.buttonBottom],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: height * 0.42, weight: .bold))
                            .foregroundStyle(isOn ? ledColor : Nexora.Colors.labelMuted)
                    }
                }
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            PanelLabel(text: title, color: labelColor, size: 8)
        }
        .help(help ?? title)
    }
}

/// Kleine Umschalt-/Auswahltaste (z. B. Filtertyp), zeigt den aktuellen Wert.
struct SelectorButton: View {
    let caption: String
    let value: String
    var width: CGFloat = 52
    var help: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Text(value)
                    .font(Nexora.Fonts.value(8.5))
                    .foregroundStyle(Nexora.Colors.turquoise)
                    .frame(width: width, height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Nexora.Colors.display))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Nexora.Colors.turquoise.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            PanelLabel(text: caption, size: 7.5)
        }
        .help(help ?? caption)
    }
}

/// Segment-Auswahl im Drawer (dunkles Design).
struct SegmentPicker<Value: Hashable>: View {
    let options: [Value]
    let selection: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    Text(title(option))
                        .font(Nexora.Fonts.value(9))
                        .foregroundStyle(option == selection ? Nexora.Colors.display : Nexora.Colors.labelLight)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 3)
                            .fill(option == selection ? Nexora.Colors.turquoise : Nexora.Colors.panel))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
