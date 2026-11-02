import SwiftUI
import NexoraCore

/// 16 Pads in zwei Reihen zu je acht (Pads 1–8 oben, 9–16 unten), jedes mit LED in der Mitte.
struct PadGridView: View {
    static let padSize: CGFloat = 105
    static let spacing: CGFloat = 12
    static let groupGap: CGFloat = 30

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Self.spacing) {
                    ForEach(0..<8, id: \.self) { column in
                        PadView(index: row * 8 + column, size: Self.padSize)
                            .padding(.trailing, column == 3 ? Self.groupGap - Self.spacing : 0)
                    }
                }
            }
        }
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
        let led = ledState(hasSample: hasSample, selected: selected)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.padIdleTop, Nexora.Colors.padIdle], startPoint: .top, endPoint: .bottom))
            // Gummioberfläche: leichte Innenkante
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.10), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            // Lichtschein der LED im Pad
            Circle()
                .fill(RadialGradient(colors: [led.color.opacity(0.55 * led.intensity), led.color.opacity(0)],
                                     center: .center, startRadius: 2, endRadius: size * 0.55))
                .frame(width: size, height: size)
            // LED
            Circle()
                .fill(led.intensity > 0.02 ? led.color : Color(hex: 0x3A2A30))
                .opacity(0.35 + 0.65 * led.intensity)
                .frame(width: size * 0.15, height: size * 0.15)
                .overlay(Circle().fill(Color.white.opacity(0.55 * led.intensity)).frame(width: size * 0.06, height: size * 0.06))
                .shadow(color: led.color.opacity(led.intensity), radius: 8 * led.intensity)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(index + 1)").font(Nexora.Fonts.value(8.5))
                    Spacer()
                    if controller.loadingPads.contains(index) {
                        ProgressView().controlSize(.mini)
                    } else if !config.keyboardKey.isEmpty {
                        Text(config.keyboardKey.uppercased()).font(Nexora.Fonts.value(8))
                    }
                }
                Spacer()
                Text(caption(config: config, hasSample: hasSample))
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Nexora.Colors.labelMuted.opacity(0.75))
            .padding(7)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(dropTargeted ? Nexora.Colors.turquoise : (selected && controller.padMode == .play ? Nexora.Colors.violetGlow.opacity(0.7) : Color.clear),
                              lineWidth: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 3)
        .scaleEffect(pressed ? 0.96 : 1)
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

    private struct LED {
        var color: Color
        var intensity: Double
    }

    private func caption(config: PadConfig, hasSample: Bool) -> String {
        switch controller.padMode {
        case .play: return hasSample ? config.name : "EMPTY"
        case .step: return "STEP \(index + 1)"
        case .keyboard:
            guard let semi = SamplerController.keyboardSemitone(forPad: index) else { return "" }
            let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            return names[(semi % 12 + 12) % 12] + (semi >= 12 ? "'" : "")
        }
    }

    private func ledState(hasSample: Bool, selected: Bool) -> LED {
        let glow = controller.meters.padGlow[index]
        switch controller.padMode {
        case .step:
            let pattern = controller.project.currentPattern
            let step = pattern[controller.selectedPad, index]
            let inRange = index < pattern.length
            if controller.meters.transport != .stopped && controller.meters.currentStep == index {
                return LED(color: Nexora.Colors.violetGlow, intensity: 1)
            }
            if step.active && inRange { return LED(color: Nexora.Colors.ledRed, intensity: 0.45 + 0.55 * step.velocity) }
            return LED(color: Nexora.Colors.ledRed, intensity: inRange ? 0.05 : 0)
        case .keyboard:
            guard let semi = SamplerController.keyboardSemitone(forPad: index) else { return LED(color: .clear, intensity: 0) }
            let black = [1, 3, 6, 8, 10].contains((semi % 12 + 12) % 12)
            let base = black ? Nexora.Colors.blueGlow : Color.white
            return LED(color: base, intensity: pressed ? 1 : 0.35)
        case .play:
            if selected { return LED(color: Nexora.Colors.violetGlow, intensity: max(0.75, glow)) }
            let idle = hasSample ? 0.3 : 0
            return LED(color: Nexora.Colors.ledRed, intensity: max(idle, glow))
        }
    }

    private func helpText(config: PadConfig, hasSample: Bool) -> String {
        let note = SamplerController.noteName(controller.project.midi.padNotes[index])
        let key = config.keyboardKey.isEmpty ? "–" : config.keyboardKey.uppercased()
        return "Pad \(index + 1): \(hasSample ? config.name : "leer") · Taste \(key) · MIDI \(note). Audiodatei hierher ziehen zum Laden."
    }
}
