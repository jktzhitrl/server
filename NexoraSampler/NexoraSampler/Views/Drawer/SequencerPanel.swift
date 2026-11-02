import SwiftUI
import AppKit
import NexoraCore

/// Step-Sequencer: 16 Spuren × 16 Schritte, Pattern-Verwaltung, Swing, Quantisierung.
struct SequencerPanel: View {
    @Environment(SamplerController.self) private var controller
    @State private var patternName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            StepGridView()
            VStack(alignment: .leading, spacing: 10) {
                DrawerSection(title: "Pattern \(SequencerState.slotName(controller.project.sequencer.currentPattern))") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 2) {
                            ForEach(0..<SequencerState.patternSlots, id: \.self) { slot in
                                Button(SequencerState.slotName(slot)) { controller.selectPattern(slot) }
                                    .buttonStyle(.plain)
                                    .font(Nexora.Fonts.label(10))
                                    .frame(width: 22, height: 20)
                                    .foregroundStyle(slot == controller.project.sequencer.currentPattern ? Nexora.Colors.display : Nexora.Colors.labelLight)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(slot == controller.project.sequencer.currentPattern ? Nexora.Colors.pink : Nexora.Colors.panel))
                            }
                        }
                        HStack(spacing: 6) {
                            Stepper("Länge: \(controller.currentPattern.length)",
                                    value: Binding(get: { controller.currentPattern.length }, set: { controller.setPatternLength($0) }),
                                    in: 1...SequencerPattern.maxSteps)
                            Button("×2") { controller.setPatternLength(min(SequencerPattern.maxSteps, controller.currentPattern.length * 2)) }
                                .help("Länge verdoppeln (bis 64 Schritte)")
                            PagePicker()
                        }
                        HStack(spacing: 10) {
                            Toggle("Seite folgt Wiedergabe", isOn: Binding(get: { controller.followPage }, set: { controller.followPage = $0 }))
                                .toggleStyle(.checkbox)
                            Toggle("Wechsel am Taktende", isOn: Binding(get: { controller.project.sequencer.switchAtBarEnd },
                                                                       set: { controller.setSwitchAtBarEnd($0) }))
                                .toggleStyle(.checkbox)
                        }
                        HStack(spacing: 6) {
                            Button("Kopieren") { controller.copyPattern() }
                            Button("Einfügen") { controller.pastePattern() }.disabled(controller.patternClipboard == nil)
                            Button("Leeren") { controller.clearCurrentPattern() }
                        }
                    }
                }
                DrawerSection(title: "Timing") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .tempo)
                        DrawerKnob(id: .swing)
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Rec-Quantisierung", selection: Binding(get: { controller.project.sequencer.quantize },
                                                                          set: { controller.setQuantize($0) })) {
                                ForEach(QuantizeMode.allCases, id: \.self) { Text($0.shortName).tag($0) }
                            }
                            .frame(width: 170)
                            Button("Pattern quantisieren") { controller.quantizeCurrentPattern() }
                                .help("Entfernt Mikro-Timing und rastet Noten auf das gewählte Raster")
                        }
                    }
                }
                DrawerSection(title: "Pattern-Presets") {
                    HStack(spacing: 6) {
                        TextField("Name", text: $patternName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Button("Speichern") {
                            controller.savePatternPreset(named: patternName)
                            patternName = ""
                        }
                        .disabled(patternName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Menu("Laden") {
                            let _ = controller.presetRevision
                            ForEach(controller.presets.list(.pattern)) { info in
                                Button(info.name) { controller.loadPatternPreset(info, applyTempo: true) }
                            }
                        }
                        .frame(width: 70)
                    }
                }
            }
            .font(.system(size: 11))
            .frame(width: 400)
        }
    }
}

/// Auswahl der sichtbaren Seite (je 16 Schritte).
struct PagePicker: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<SequencerPattern.pageCount, id: \.self) { page in
                let first = page * SequencerPattern.stepsPerPage
                let playingHere = controller.meters.transport != .stopped && controller.meters.currentStep / SequencerPattern.stepsPerPage == page
                Button("\(first + 1)–\(first + SequencerPattern.stepsPerPage)") { controller.setStepPage(page) }
                    .buttonStyle(.plain)
                    .font(Nexora.Fonts.value(8.5))
                    .frame(width: 40, height: 20)
                    .foregroundStyle(page == controller.stepPage ? Nexora.Colors.display : Nexora.Colors.labelLight)
                    .background(RoundedRectangle(cornerRadius: 3).fill(page == controller.stepPage ? Nexora.Colors.turquoise : Nexora.Colors.panel))
                    .overlay(alignment: .bottom) { if playingHere { Rectangle().fill(Nexora.Colors.pink).frame(height: 2) } }
                    .opacity(page < controller.pageCount ? 1 : 0.35)
                    .help("Seite \(page + 1): Schritte \(first + 1)–\(first + SequencerPattern.stepsPerPage)")
            }
        }
    }
}

/// Das Raster: 16 Spuren × 16 Schritte der gewählten Seite. Klick: Schritt an/aus · ⇧-Klick: Anschlagstärke wechseln.
struct StepGridView: View {
    @Environment(SamplerController.self) private var controller
    private let cellWidth: CGFloat = 34
    private let cellHeight: CGFloat = 12

    var body: some View {
        let pattern = controller.currentPattern
        let playing = controller.meters.transport != .stopped
        let current = controller.meters.currentStep
        let offset = controller.stepPage * SequencerPattern.stepsPerPage
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text("TRACK").frame(width: 92, alignment: .leading)
                Text("M").frame(width: 16)
                Text("S").frame(width: 16)
                ForEach(offset..<(offset + SequencerPattern.stepsPerPage), id: \.self) { step in
                    Text("\(step + 1)")
                        .frame(width: cellWidth)
                        .foregroundStyle(playing && current == step ? Nexora.Colors.pink : Nexora.Colors.labelMuted)
                }
                Text("GATE").frame(width: 44)
            }
            .font(Nexora.Fonts.value(8))
            .foregroundStyle(Nexora.Colors.labelMuted)
            ForEach(0..<SequencerPattern.trackCount, id: \.self) { track in
                trackRow(track, pattern: pattern, playing: playing, current: current, offset: offset)
            }
        }
    }

    private func trackRow(_ track: Int, pattern: SequencerPattern, playing: Bool, current: Int, offset: Int) -> some View {
        let seq = controller.project.sequencer
        let selected = controller.selectedPad == track
        return HStack(spacing: 2) {
            Button {
                controller.selectPad(track)
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(Nexora.Colors.pink.opacity(controller.meters.padGlow[track])).frame(width: 5, height: 5)
                    Text(String(format: "%02d %@", track + 1, controller.project.pads[track].name))
                        .lineLimit(1)
                }
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(selected ? Nexora.Colors.turquoise : Nexora.Colors.labelLight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            smallToggle("M", on: seq.trackMutes[track], color: Color(hex: 0xFFD166)) { controller.toggleMute(track) }
            smallToggle("S", on: seq.trackSolos[track], color: Nexora.Colors.turquoise) { controller.toggleSolo(track) }
            ForEach(offset..<(offset + SequencerPattern.stepsPerPage), id: \.self) { step in
                StepCell(step: pattern[track, step], inRange: step < pattern.length,
                         isCurrent: playing && current == step, beat: step % 4 == 0,
                         width: cellWidth, height: cellHeight)
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.shift) {
                            controller.cycleStepVelocity(track: track, step: step)
                        } else {
                            controller.toggleStep(track: track, step: step)
                        }
                    }
            }
            Stepper(value: Binding(get: { pattern.gates[track] }, set: { controller.setTrackGate(track, steps: $0) }),
                    in: 0.25...16, step: 0.25) {
                Text(String(format: "%.2g", pattern.gates[track])).frame(width: 22, alignment: .trailing)
            }
            .controlSize(.mini)
            .frame(width: 44)
            .help("Notenlänge in Schritten (für Pads im Gate-/Loop-Modus)")
        }
        .font(Nexora.Fonts.value(8.5))
        .frame(height: cellHeight + 1)
    }

    private func smallToggle(_ label: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Nexora.Fonts.label(8))
                .frame(width: 16, height: cellHeight)
                .foregroundStyle(on ? Nexora.Colors.display : Nexora.Colors.labelMuted)
                .background(RoundedRectangle(cornerRadius: 2).fill(on ? color : Nexora.Colors.panel))
        }
        .buttonStyle(.plain)
        .help(label == "M" ? "Spur stummschalten" : "Spur solo")
    }
}

private struct StepCell: View {
    let step: SequencerStep
    let inRange: Bool
    let isCurrent: Bool
    let beat: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill)
            if step.active && abs(step.offset) > 0.01 {
                // Mikro-Timing-Markierung
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: height - 4)
                    .offset(x: CGFloat(0.5 + step.offset) * (width - 2))
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(isCurrent ? Nexora.Colors.pink : Color.clear, lineWidth: 1))
        .shadow(color: step.active && inRange ? Nexora.Colors.blueGlow.opacity(0.6) : .clear, radius: 3)
        .contentShape(Rectangle())
        .opacity(inRange ? 1 : 0.3)
    }

    private var fill: Color {
        if step.active {
            return Nexora.Colors.blueGlow.opacity(0.35 + 0.65 * step.velocity)
        }
        return beat ? Nexora.Colors.panelLine.opacity(0.9) : Nexora.Colors.panel
    }
}
