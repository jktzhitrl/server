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
    var labelColor: Color = Nexora.Colors.bodyLabel
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

/// Gummi-Taste mit aufgedruckter Beschriftung, die bei Aktivierung farbig leuchtet
/// (wie bei Hardware-Grooveboxen).
struct FaceButton: View {
    let title: String
    var symbol: String?
    var isLit = false
    var litColor: Color = Nexora.Colors.ledRed
    /// Volle Hintergrundbeleuchtung (z. B. Play) statt leuchtender Kontur
    var fillWhenLit = false
    var width: CGFloat = 70
    var height: CGFloat = 26
    var fontSize: CGFloat = 10.5
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: fillWhenLit && isLit
                                         ? [litColor.opacity(0.95), litColor.opacity(0.65)]
                                         : [Nexora.Colors.buttonTop, Nexora.Colors.buttonBottom],
                                         startPoint: .top, endPoint: .bottom))
                if isLit && !fillWhenLit {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(litColor.opacity(0.16))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(litColor.opacity(0.95), lineWidth: 1.5)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                HStack(spacing: 4) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: fontSize * 1.25, weight: .bold))
                    }
                    if !title.isEmpty {
                        Text(title).font(.system(size: fontSize, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(isLit ? (fillWhenLit ? Color.white : litColor.opacity(0.95)) : Nexora.Colors.buttonText.opacity(0.88))
                .shadow(color: isLit ? litColor.opacity(0.9) : .clear, radius: 4)
                .padding(.horizontal, 4)
            }
            .frame(width: width, height: height)
            .shadow(color: isLit ? litColor.opacity(0.55) : Color.black.opacity(0.45), radius: isLit ? 6 : 2, x: 0, y: isLit ? 0 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help ?? title)
        .animation(.easeOut(duration: 0.12), value: isLit)
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
