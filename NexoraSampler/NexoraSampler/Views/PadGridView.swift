import SwiftUI
import NexoraCore

/// 16 leuchtende Drum-Pads im 4×4-Raster (Pad 1 unten links, wie bei Hardware-Samplern).
struct PadGridView: View {
    static let padSize: CGFloat = 74
    static let spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach((0..<4).reversed(), id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<4, id: \.self) { column in
                        PadView(index: row * 4 + column, size: Self.padSize)
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Nexora.Colors.panel.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 3)
        )
    }
}

struct PadView: View {
    @Environment(SamplerController.self) private var controller
    let index: Int
    let size: CGFloat
    @State private var pressed = false
    @State private var dropTargeted = false

    var body: some View {
        let config = controller.project.pads[index]
        let hasSample = controller.padSamples[index] != nil
        let selected = controller.selectedPad == index
        let visual = visualState(hasSample: hasSample)
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [hasSample ? Nexora.Colors.padIdleTop : Nexora.Colors.padEmpty, Nexora.Colors.padIdle],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RadialGradient(colors: [visual.color.opacity(0.95), visual.color.opacity(0.35)], center: .center,
                                     startRadius: 2, endRadius: size * 0.7))
                .opacity(visual.intensity)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor(selected: selected), lineWidth: selected || dropTargeted ? 2 : 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%02d", index + 1))
                        .font(Nexora.Fonts.value(8.5))
                    Spacer()
                    if controller.loadingPads.contains(index) {
                        ProgressView().controlSize(.mini)
                    } else if !config.keyboardKey.isEmpty {
                        Text(config.keyboardKey.uppercased())
                            .font(Nexora.Fonts.value(8))
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.3)))
                    }
                }
                Spacer()
                Text(controller.padMode == .step ? String(format: "STEP %d", index + 1) : (hasSample ? config.name : "EMPTY"))
                    .font(Nexora.Fonts.label(8.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Nexora.Colors.labelLight.opacity(hasSample || controller.padMode == .step ? 0.9 : 0.45))
            .padding(6)
        }
        .frame(width: size, height: size)
        .shadow(color: visual.color.opacity(visual.intensity * 0.9), radius: 12 * visual.intensity)
        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.07), value: pressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !pressed else { return }
                    pressed = true
                    let velocity: Float
                    if AppPreferences.velocityFromPosition {
                        // Oben = laut, unten = leise
                        velocity = Float(max(0.25, min(1, 1 - value.startLocation.y / size * 0.75)))
                    } else {
                        velocity = AppPreferences.keyboardVelocity
                    }
                    controller.padDown(index, velocity: velocity)
                }
                .onEnded { _ in
                    pressed = false
                    controller.padUp(index)
                }
        )
        .dropDestination(for: URL.self) { urls, _ in
            controller.handleDrop(urls, onPad: index)
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Auswählen") { controller.selectPad(index) }
            Button("Sample laden …") {
                controller.selectedPad = index
                controller.chooseSampleForSelectedPad()
            }
            Button("Im Pad-Editor bearbeiten") {
                controller.selectedPad = index
                controller.drawer = .editor
            }
            Button("MIDI-Note lernen") {
                controller.noteLearnPad = index
                controller.showLCD(String(format: "PAD %02d", index + 1), "PLAY A MIDI NOTE", seconds: 3)
            }
            Divider()
            Button("Spur im Pattern löschen") { controller.clearTrack(index) }
            Button("Pad leeren", role: .destructive) { controller.clearPad(index) }
        }
        .help(helpText(config: config, hasSample: hasSample))
    }

    private struct Visual {
        var color: Color
        var intensity: Double
    }

    private func visualState(hasSample: Bool) -> Visual {
        if controller.padMode == .step {
            let pattern = controller.project.currentPattern
            let track = controller.selectedPad
            let step = pattern[track, index]
            let inRange = index < pattern.length
            let current = controller.meters.transport != .stopped && controller.meters.currentStep == index
            if current { return Visual(color: Nexora.Colors.pink, intensity: 0.95) }
            if step.active && inRange { return Visual(color: Nexora.Colors.blueGlow, intensity: 0.35 + 0.5 * step.velocity) }
            return Visual(color: Nexora.Colors.blueGlow, intensity: inRange ? 0.04 : 0)
        }
        let glow = controller.meters.padGlow[index]
        return Visual(color: Nexora.Colors.pink, intensity: hasSample ? glow : glow * 0.3)
    }

    private func borderColor(selected: Bool) -> Color {
        if dropTargeted { return Nexora.Colors.pink }
        return selected ? Nexora.Colors.turquoise : Color.white.opacity(0.08)
    }

    private func helpText(config: PadConfig, hasSample: Bool) -> String {
        let note = SamplerController.noteName(controller.project.midi.padNotes[index])
        let key = config.keyboardKey.isEmpty ? "–" : config.keyboardKey.uppercased()
        return "Pad \(index + 1): \(hasSample ? config.name : "leer") · Taste \(key) · MIDI \(note). Audiodatei hierher ziehen zum Laden."
    }
}
