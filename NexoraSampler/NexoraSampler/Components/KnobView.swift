import SwiftUI
import AppKit

/// Kreisförmiger Drehregler im Hardware-Stil.
/// - Ziehen (vertikal oder horizontal) ändert den Wert, ⌥ oder ⇧ für Feineinstellung.
/// - Doppelklick setzt auf den Standardwert zurück.
/// - Funktioniert mit Maus und Trackpad.
struct KnobView: View {
    let title: String
    /// Normierter Wert 0 ... 1
    let value: Double
    let defaultValue: Double
    let valueText: String
    var size: CGFloat = 42
    var accent: Color = Nexora.Colors.turquoise
    var labelColor: Color = Nexora.Colors.labelDark
    var isLearning = false
    var hasMapping = false
    let onChange: (Double) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    @State private var dragStartValue: Double?
    @State private var hovering = false

    private static let startAngle = -135.0
    private static let sweep = 270.0

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 10, height: size + 10)
                Circle()
                    .trim(from: 0, to: 0.75 * min(max(value, 0), 1))
                    .stroke(isLearning ? Nexora.Colors.pink : accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 10, height: size + 10)
                    .shadow(color: (isLearning ? Nexora.Colors.pink : accent).opacity(0.7), radius: 3)
                Circle()
                    .fill(RadialGradient(colors: [Nexora.Colors.knobHighlight, Nexora.Colors.knobBlue, Nexora.Colors.knobShadow],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.8))
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.38), radius: 4, x: 0, y: 3)
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .frame(width: size, height: size)
                Circle()
                    .fill(Nexora.Colors.knobShadow.opacity(0.35))
                    .frame(width: size * 0.55, height: size * 0.55)
                    .blur(radius: 1)
                Capsule()
                    .fill(Nexora.Colors.knobMark)
                    .frame(width: 3, height: size * 0.3)
                    .offset(y: -size * 0.27)
                    .rotationEffect(.degrees(Self.startAngle + Self.sweep * min(max(value, 0), 1)))
                if hasMapping {
                    Circle().fill(Nexora.Colors.pink).frame(width: 4, height: 4)
                        .offset(x: size * 0.5, y: -size * 0.5)
                }
            }
            .frame(width: size + 14, height: size + 14)
            .contentShape(Circle())
            .gesture(dragGesture)
            .simultaneousGesture(TapGesture(count: 2).onEnded { onChange(defaultValue) })
            .simultaneousGesture(TapGesture(count: 1).onEnded { onBegin() })
            .onHover { hovering = $0 }

            Text(title)
                .font(Nexora.Fonts.label(8.5))
                .tracking(0.8)
                .foregroundStyle(labelColor)
                .lineLimit(1)
            Text(valueText)
                .font(Nexora.Fonts.value(8))
                .foregroundStyle(labelColor.opacity(hovering || dragStartValue != nil ? 0.95 : 0.6))
                .lineLimit(1)
        }
        .frame(minWidth: size + 16)
        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.9), value: value)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = value
                    onBegin()
                }
                let flags = NSEvent.modifierFlags
                let fine = flags.contains(.option) || flags.contains(.shift)
                let sensitivity = fine ? 1_000.0 : 200.0
                let delta = (Double(-gesture.translation.height) + Double(gesture.translation.width)) / sensitivity
                onChange(min(max((dragStartValue ?? value) + delta, 0), 1))
            }
            .onEnded { _ in
                dragStartValue = nil
                onEnd()
            }
    }
}
