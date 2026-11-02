import SwiftUI
import NexoraCore

/// Großes XY-Touchpad: X- und Y-Achse steuern zwei frei zuweisbare Parameter in Echtzeit.
struct XYPadView: View {
    @Environment(SamplerController.self) private var controller
    @State private var touching = false
    @State private var trail: [CGPoint] = []
    @State private var restore: (x: Double, y: Double)?

    /// Parameter, die sinnvoll auf das XY-Pad gelegt werden können.
    static let assignable: [ParameterID] = [
        .masterFilterCutoff, .masterFilterResonance, .reverbMix, .reverbSize, .delayMix, .delayFeedback, .delayTime,
        .masterDrive, .masterCrushBits, .masterCrushRate, .modRate, .modDepth, .eqLow, .eqHigh, .compThreshold,
        .masterVolume, .padPitch, .padCutoff, .padResonance, .padStart, .padDecay, .padPan, .padLFORate, .padLFODepth, .swing
    ]

    var body: some View {
        let xID = controller.project.xyPad.xParameter
        let yID = controller.project.xyPad.yParameter
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                axisMenu(axis: .x, current: xID)
                axisMenu(axis: .y, current: yID)
                Spacer()
                Text("TOUCH PAD")
                    .font(Nexora.Fonts.label(8))
                    .tracking(1.2)
                    .foregroundStyle(Nexora.Colors.bodyLabelMuted)
            }
            GeometryReader { geo in
                let size = geo.size
                let x = controller.normalizedValue(xID)
                let y = controller.normalizedValue(yID)
                let point = CGPoint(x: x * size.width, y: (1 - y) * size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Nexora.Colors.display)
                    XYGrid()
                        .stroke(Nexora.Colors.turquoise.opacity(0.12), lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Fadenkreuz
                    Path { p in
                        p.move(to: CGPoint(x: point.x, y: 0)); p.addLine(to: CGPoint(x: point.x, y: size.height))
                        p.move(to: CGPoint(x: 0, y: point.y)); p.addLine(to: CGPoint(x: size.width, y: point.y))
                    }
                    .stroke(Nexora.Colors.pink.opacity(touching ? 0.35 : 0.15), lineWidth: 1)
                    // Leuchtspur
                    ForEach(Array(trail.enumerated()), id: \.offset) { i, p in
                        Circle()
                            .fill(Nexora.Colors.pink.opacity(Double(i) / Double(max(trail.count, 1)) * 0.35))
                            .frame(width: 8, height: 8)
                            .position(p)
                    }
                    Circle()
                        .fill(RadialGradient(colors: [Color.white, Nexora.Colors.pink, Nexora.Colors.pink.opacity(0)],
                                             center: .center, startRadius: 1, endRadius: touching ? 22 : 15))
                        .frame(width: touching ? 44 : 30, height: touching ? 44 : 30)
                        .shadow(color: Nexora.Colors.pink, radius: touching ? 14 : 8)
                        .position(point)
                        .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.85), value: touching)
                    VStack {
                        HStack {
                            Text("Y \(controller.displayValue(yID))")
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            Text("X \(controller.displayValue(xID))")
                        }
                    }
                    .font(Nexora.Fonts.value(9))
                    .foregroundStyle(Nexora.Colors.turquoise.opacity(0.8))
                    .padding(8)
                    .allowsHitTesting(false)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !touching {
                                touching = true
                                restore = (x, y)
                            }
                            let nx = min(max(value.location.x / size.width, 0), 1)
                            let ny = min(max(1 - value.location.y / size.height, 0), 1)
                            controller.setXY(x: nx, y: ny)
                            trail.append(CGPoint(x: nx * size.width, y: (1 - ny) * size.height))
                            if trail.count > 14 { trail.removeFirst(trail.count - 14) }
                        }
                        .onEnded { _ in
                            touching = false
                            trail.removeAll()
                            if !controller.xyLatch, let r = restore {
                                controller.setXY(x: r.x, y: r.y)
                            }
                            restore = nil
                        }
                )
            }
            .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 3)
        }
        .help("XY-Pad: Maus oder Trackpad ziehen. Achsen über die Menüs oben oder per Rechtsklick auf einen Regler zuweisen.")
    }

    private func axisMenu(axis: XYAxis, current: ParameterID) -> some View {
        Menu {
            ForEach(Self.assignable, id: \.self) { id in
                Button {
                    controller.assignXY(axis: axis, parameter: id)
                } label: {
                    if id == current { Label(id.spec.name, systemImage: "checkmark") } else { Text(id.spec.name) }
                }
            }
        } label: {
            Text("\(axis == .x ? "X" : "Y"): \(current.spec.shortName)")
                .font(Nexora.Fonts.value(9))
                .foregroundStyle(Nexora.Colors.turquoise)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 4).fill(Nexora.Colors.display))
    }
}

private struct XYGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1..<8 {
            let x = rect.width * CGFloat(i) / 8
            let y = rect.height * CGFloat(i) / 8
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return p
    }
}
