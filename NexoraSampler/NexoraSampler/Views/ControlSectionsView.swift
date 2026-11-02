import SwiftUI
import NexoraCore

/// Daten-Regler, Navigation und die fünf Regler-Sektionen
/// (Sample, Filter, Modulation, Amp/EG, Insert Fx). Alle Sektionen wirken auf das ausgewählte Pad.
struct ControlSectionsView: View {
    @Environment(SamplerController.self) private var controller

    private let bigKnob: CGFloat = 60
    private let smallKnob: CGFloat = 36

    var body: some View {
        let pad = controller.selectedPad
        let s = controller.project.pads[pad].settings
        HStack(alignment: .top, spacing: 0) {
            navigationBlock
                .frame(width: 150, alignment: .leading)
            section("Sample", width: 130) {
                ParameterKnob(id: .padStart, title: "", size: bigKnob)
            } row2: {
                ParameterKnob(id: .padPitch, title: "Pitch", size: smallKnob)
            } row3: {
                ParameterKnob(id: .padEnd, title: "End", size: smallKnob)
            }
            section("Filter", width: 180) {
                ParameterKnob(id: .padCutoff, title: "", size: bigKnob)
            } row2: {
                HStack(spacing: 10) {
                    ParameterKnob(id: .padResonance, title: "Resonance", size: smallKnob)
                    ParameterKnob(id: .padFilterEnv, title: "EG Int", size: smallKnob)
                }
            } row3: {
                HStack(spacing: 6) {
                    filterButton("LPF", .lowPass, s.filterMode)
                    filterButton("HPF", .highPass, s.filterMode)
                    filterButton("BPF", .bandPass, s.filterMode)
                }
                .padding(.top, 14)
            }
            section("Modulation", width: 140) {
                ParameterKnob(id: .padLFODepth, title: "", size: bigKnob)
            } row2: {
                ParameterKnob(id: .padLFORate, title: "Speed", size: smallKnob)
            } row3: {
                VStack(spacing: 6) {
                    FaceButton(title: s.lfoTarget == .off ? "Mod Off" : "→ \(s.lfoTarget.shortName)",
                               isLit: s.lfoTarget != .off, width: 82, height: 24,
                               help: "Modulationsziel: Vibrato, Tremolo, Filter, Auto-Pan oder aus") {
                        controller.updatePad(pad) { $0.settings.lfoTarget = $0.settings.lfoTarget.next }
                        controller.showLCD("MOD TARGET", controller.project.pads[pad].settings.lfoTarget.shortName)
                    }
                    FaceButton(title: "Wave \(s.lfoShape.shortName)", width: 82, height: 24, help: "LFO-Wellenform") {
                        controller.updatePad(pad) { $0.settings.lfoShape = $0.settings.lfoShape.next }
                        controller.showLCD("LFO WAVE", controller.project.pads[pad].settings.lfoShape.shortName)
                    }
                }
                .padding(.top, 4)
            }
            section("Amp/EG", width: 190) {
                HStack(spacing: 16) {
                    ParameterKnob(id: .padVolume, title: "Level", size: 44)
                    ParameterKnob(id: .padPan, title: "Pan", size: 44)
                }
            } row2: {
                HStack(spacing: 16) {
                    ParameterKnob(id: .padAttack, title: "Attack", size: smallKnob)
                    ParameterKnob(id: .padDecay, title: "Decay", size: smallKnob)
                    ParameterKnob(id: .padRelease, title: "Release", size: smallKnob)
                }
            } row3: {
                HStack(spacing: 8) {
                    FaceButton(title: "MFX Send", isLit: s.reverbSend > 0 || s.delaySend > 0, width: 80, height: 26,
                               help: "Send des Pads zu Hall und Delay ein/aus") {
                        controller.updatePad(pad) {
                            let on = $0.settings.reverbSend > 0 || $0.settings.delaySend > 0
                            $0.settings.reverbSend = on ? 0 : 1
                            $0.settings.delaySend = on ? 0 : 1
                        }
                    }
                    FaceButton(title: s.playMode == .oneShot ? "One Shot" : (s.playMode == .gate ? "Amp EG" : "Loop"),
                               isLit: s.playMode != .oneShot, width: 80, height: 26,
                               help: "Wiedergabe: One-Shot, Amp EG (Gate, Release beim Loslassen) oder Loop") {
                        controller.updatePad(pad) { $0.settings.playMode = $0.settings.playMode.next }
                    }
                }
                .padding(.top, 14)
            }
            section("Insert Fx", width: 134) {
                ParameterKnob(id: .padDrive, title: "", size: bigKnob)
            } row2: {
                ParameterKnob(id: .padCrushBits, title: "Edit", size: smallKnob)
            } row3: {
                VStack(spacing: 6) {
                    FaceButton(title: "IFX On", isLit: s.insertFXOn, width: 72, height: 24, help: "Insert-Effekte (Drive, Bitcrusher) ein/aus") {
                        controller.updatePad(pad) { $0.settings.insertFXOn.toggle() }
                    }
                    FaceButton(title: s.reverse ? "◀ Reverse" : "Reverse", isLit: s.reverse, width: 72, height: 24,
                               help: "Sample rückwärts abspielen") {
                        controller.updatePad(pad) { $0.settings.reverse.toggle() }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var navigationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParameterKnob(id: .tempo, title: "Tempo", size: 66, style: .jog)
                .frame(width: 140, alignment: .leading)
                .padding(.top, 22)
            HStack(spacing: 10) {
                FaceButton(title: "", symbol: "chevron.left", width: 58, height: 24, help: "Vorheriges Pattern") { controller.stepPattern(by: -1) }
                FaceButton(title: "", symbol: "chevron.right", width: 58, height: 24, help: "Nächstes Pattern") { controller.stepPattern(by: 1) }
            }
            HStack(spacing: 10) {
                FaceButton(title: "Edit", isLit: controller.drawer == .editor, width: 58, height: 24, help: "Pad-Editor") { controller.toggleDrawer(.editor) }
                FaceButton(title: "Exit", width: 58, height: 24, help: "Bereich schließen / Modus verlassen") { controller.exitAction() }
            }
            HStack(spacing: 10) {
                FaceButton(title: "Browse", isLit: controller.drawer == .browser, width: 58, height: 24, help: "Sample-Browser") { controller.toggleDrawer(.browser) }
                FaceButton(title: "Kit", isLit: controller.drawer == .kits, width: 58, height: 24, help: "Kits & Presets") { controller.toggleDrawer(.kits) }
            }
        }
    }

    private func filterButton(_ title: String, _ mode: FilterMode, _ current: FilterMode) -> some View {
        FaceButton(title: title, isLit: current == mode, width: 50, height: 26, help: "Pad-Filter \(title) – erneut drücken schaltet aus") {
            controller.updatePad(controller.selectedPad) { $0.settings.filterMode = $0.settings.filterMode == mode ? .off : mode }
            controller.showLCD("FILTER", controller.project.pads[controller.selectedPad].settings.filterMode.shortName)
        }
    }

    private func section<A: View, B: View, C: View>(_ title: String, width: CGFloat,
                                                    @ViewBuilder big: () -> A,
                                                    @ViewBuilder row2: () -> B,
                                                    @ViewBuilder row3: () -> C) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Nexora.Fonts.section(22))
                .foregroundStyle(Nexora.Colors.bodyLabel)
                .frame(height: 30)
            big().frame(height: 96)
            row2().frame(height: 78)
            row3().frame(height: 86, alignment: .top)
        }
        .frame(width: width)
    }
}
