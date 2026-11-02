import SwiftUI
import AppKit

/// Kreisförmiger Drehregler im Hardware-Stil.
/// - Ziehen (vertikal oder horizontal) ändert den Wert, ⌥ oder ⇧ für Feineinstellung.
/// - Doppelklick setzt auf den Standardwert zurück.
/// - Funktioniert mit Maus und Trackpad.
struct KnobView: View {
    enum Style { case standard, jog }

    let title: String
    /// Normierter Wert 0 ... 1
    let value: Double
    let defaultValue: Double
    let valueText: String
    var size: CGFloat = 42
    var style: Style = .standard
    var labelColor: Color = Nexora.Colors.bodyLabel
    var showsValue = true
    var isLearning = false
    var hasMapping = false
    let onChange: (Double) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    @State private var dragStartValue: Double?
    @State private var hovering = false

    private static let startAngle = -135.0
    private static let sweep = 270.0

    private var clamped: Double { min(max(value, 0), 1) }
    private var ringColor: Color { isLearning ? Nexora.Colors.pink : Nexora.Colors.knobRing }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Wertebogen
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 12, height: size + 12)
                Circle()
                    .trim(from: 0, to: 0.75 * clamped)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 12, height: size + 12)
                    .shadow(color: ringColor.opacity(0.6), radius: 2)
                // Rock (dunkler Sockel)
                Circle()
                    .fill(LinearGradient(colors: [Nexora.Colors.knobSkirt.opacity(0.95), Color.black.opacity(0.9)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size + 3, height: size + 3)
                    .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 4)
                // Kappe
                Circle()
                    .fill(RadialGradient(colors: capColors, center: UnitPoint(x: 0.4, y: 0.28),
                                         startRadius: 1, endRadius: size * 0.75))
                    .frame(width: size * 0.9, height: size * 0.9)
                Circle()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                    .frame(width: size * 0.9, height: size * 0.9)
                if style == .jog {
                    // Griffmulde
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: size * 0.18, height: size * 0.18)
                        .offset(y: -size * 0.27)
                        .rotationEffect(.degrees(Self.startAngle + Self.sweep * clamped))
                } else {
                    Capsule()
                        .fill(Nexora.Colors.knobMark)
                        .frame(width: max(2, size * 0.055), height: size * 0.3)
                        .offset(y: -size * 0.25)
                        .rotationEffect(.degrees(Self.startAngle + Self.sweep * clamped))
                }
                if hasMapping {
                    Circle().fill(Nexora.Colors.turquoise).frame(width: 4, height: 4)
                        .offset(x: size * 0.52, y: -size * 0.52)
                }
            }
            .frame(width: size + 16, height: size + 16)
            .contentShape(Circle())
            .gesture(dragGesture)
            .simultaneousGesture(TapGesture(count: 2).onEnded { onChange(defaultValue) })
            .simultaneousGesture(TapGesture(count: 1).onEnded { onBegin() })
            .onHover { hovering = $0 }

            if !title.isEmpty {
                Text(title)
                    .font(Nexora.Fonts.caption(size > 50 ? 11 : 10))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsValue {
                Text(valueText)
                    .font(Nexora.Fonts.value(8))
                    .foregroundStyle(labelColor.opacity(hovering || dragStartValue != nil ? 0.95 : 0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(minWidth: size + 16)
        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.9), value: value)
    }

    private var capColors: [Color] {
        switch style {
        case .standard: return [Nexora.Colors.knobHighlight, Nexora.Colors.knobBlue, Nexora.Colors.knobShadow]
        case .jog: return [Nexora.Colors.jogTop.opacity(0.85), Nexora.Colors.jogTop, Nexora.Colors.jogBottom]
        }
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
                let sensitivity = (fine ? 1_000.0 : 200.0) * (style == .jog ? 2.5 : 1)
                let delta = (Double(-gesture.translation.height) + Double(gesture.translation.width)) / sensitivity
                onChange(min(max((dragStartValue ?? value) + delta, 0), 1))
            }
            .onEnded { _ in
                dragStartValue = nil
                onEnd()
            }
    }
}
