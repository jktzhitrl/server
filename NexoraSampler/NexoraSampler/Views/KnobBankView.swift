import SwiftUI
import NexoraCore

/// Die zahlreichen hellblauen Drehregler in der Mitte und rechts.
/// Obere Reihe: Klang des ausgewählten Pads. Untere Reihe: Master-Filter, Modulation, Effekte, EQ.
struct KnobBankView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                PanelSection(title: String(format: "Pad %02d · Sound", controller.selectedPad + 1)) {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .padVolume, title: "VOLUME")
                        ParameterKnob(id: .padPan, title: "PAN")
                        ParameterKnob(id: .padPitch, title: "PITCH")
                        ParameterKnob(id: .padStart, title: "SAMPLE")
                        ParameterKnob(id: .padEnd, title: "END")
                        ParameterKnob(id: .padSpeed, title: "SPEED")
                    }
                }
                PanelSection(title: "Envelope") {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .padAttack, title: "ATTACK")
                        ParameterKnob(id: .padDecay, title: "DECAY")
                        ParameterKnob(id: .padSustain, title: "SUSTAIN")
                        ParameterKnob(id: .padRelease, title: "RELEASE")
                    }
                }
                PanelSection(title: "Play") {
                    VStack(spacing: 6) {
                        let s = controller.project.pads[controller.selectedPad].settings
                        SelectorButton(caption: "Mode", value: s.playMode.shortName,
                                       help: "Wiedergabemodus: One-Shot, Gate (solange gehalten) oder Loop") {
                            controller.updatePad(controller.selectedPad) { $0.settings.playMode = $0.settings.playMode.next }
                        }
                        SelectorButton(caption: "Reverse", value: s.reverse ? "◀ REV" : "FWD ▶",
                                       help: "Rückwärtswiedergabe") {
                            controller.updatePad(controller.selectedPad) { $0.settings.reverse.toggle() }
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                PanelSection(title: "Filter") {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .masterFilterCutoff, title: "FILTER")
                        ParameterKnob(id: .masterFilterResonance, title: "RESO")
                        SelectorButton(caption: "Type", value: controller.project.master.filterMode.shortName, width: 40,
                                       help: "Filtertyp: Low Pass, High Pass, Band Pass oder aus") {
                            controller.updateMaster { $0.filterMode = $0.filterMode.next }
                            controller.showLCD("FILTER TYPE", controller.project.master.filterMode.shortName)
                        }
                        .padding(.top, 12)
                    }
                }
                PanelSection(title: "Modulation") {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .modRate, title: "LFO")
                        ParameterKnob(id: .modDepth, title: "MOD")
                        SelectorButton(caption: "Target", value: controller.project.master.modTarget.shortName, width: 58,
                                       help: "Modulationsziel des LFOs: Filter, Tremolo, Vibrato oder Auto-Pan") {
                            controller.updateMaster { $0.modTarget = $0.modTarget.next }
                            controller.showLCD("MOD TARGET", controller.project.master.modTarget.shortName)
                        }
                        .padding(.top, 12)
                    }
                }
                PanelSection(title: "Effects") {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .masterDrive, title: "DRIVE")
                        ParameterKnob(id: .masterCrushBits, title: "CRUSH")
                        ParameterKnob(id: .delayMix, title: "DELAY")
                        ParameterKnob(id: .reverbMix, title: "REVERB")
                    }
                }
                PanelSection(title: "EQ · Dynamics") {
                    HStack(spacing: 4) {
                        ParameterKnob(id: .eqLow, title: "LOW")
                        ParameterKnob(id: .eqMid, title: "MID")
                        ParameterKnob(id: .eqHigh, title: "HIGH")
                        ParameterKnob(id: .compThreshold, title: "COMP")
                    }
                }
            }
        }
    }
}

/// Zyklisches Weiterschalten von Auswahlwerten.
protocol CyclingOption: CaseIterable, Equatable where AllCases == [Self] {}

extension CyclingOption {
    var next: Self {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self) else { return self }
        return all[(i + 1) % all.count]
    }
}

extension PlayMode: CyclingOption {}
extension FilterMode: CyclingOption {}
extension MasterModTarget: CyclingOption {}
extension LFOShape: CyclingOption {}
extension PadLFOTarget: CyclingOption {}
extension PitchMode: CyclingOption {}
extension TempoDivision: CyclingOption {}
