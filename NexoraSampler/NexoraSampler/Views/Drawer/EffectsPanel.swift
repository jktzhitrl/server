import SwiftUI
import NexoraCore

/// Alle Parameter der Master-Effektkette.
struct EffectsPanel: View {
    @Environment(SamplerController.self) private var controller
    @State private var presetName = ""

    var body: some View {
        let m = controller.project.master
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                DrawerSection(title: "Filter") {
                    VStack(alignment: .leading, spacing: 6) {
                        SegmentPicker(options: FilterMode.allCases, selection: m.filterMode, title: { $0.shortName }) { v in
                            controller.updateMaster { $0.filterMode = v }
                        }
                        HStack(spacing: 2) {
                            DrawerKnob(id: .masterFilterCutoff, title: "CUTOFF")
                            DrawerKnob(id: .masterFilterResonance)
                        }
                    }
                }
                DrawerSection(title: "Drive · Bitcrusher") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .masterDrive)
                        DrawerKnob(id: .masterCrushBits)
                        DrawerKnob(id: .masterCrushRate, title: "RATE")
                    }
                }
                DrawerSection(title: "Modulation (LFO)") {
                    VStack(alignment: .leading, spacing: 6) {
                        SegmentPicker(options: MasterModTarget.allCases, selection: m.modTarget, title: { $0.shortName }) { v in
                            controller.updateMaster { $0.modTarget = v }
                        }
                        HStack(spacing: 2) {
                            DrawerKnob(id: .modRate, title: "RATE")
                            DrawerKnob(id: .modDepth, title: "DEPTH")
                            SelectorButton(caption: "Shape", value: m.modShape.shortName, width: 36) {
                                controller.updateMaster { $0.modShape = $0.modShape.next }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
                DrawerSection(title: "EQ") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .eqLow)
                        DrawerKnob(id: .eqMid)
                        DrawerKnob(id: .eqMidFrequency, title: "FREQ")
                        DrawerKnob(id: .eqHigh)
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                DrawerSection(title: "Delay") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Menu("Sync: \(m.delaySync.shortName)") {
                                ForEach(TempoDivision.allCases, id: \.self) { d in
                                    Button(d.shortName) { controller.updateMaster { $0.delaySync = d } }
                                }
                            }
                            .frame(width: 110)
                            Toggle("Ping-Pong", isOn: Binding(get: { m.delayPingPong }, set: { v in controller.updateMaster { $0.delayPingPong = v } }))
                                .toggleStyle(.checkbox)
                        }
                        HStack(spacing: 2) {
                            DrawerKnob(id: .delayMix, title: "MIX")
                            DrawerKnob(id: .delayTime)
                            DrawerKnob(id: .delayFeedback)
                            DrawerKnob(id: .delayDamping, title: "TONE")
                        }
                    }
                }
                DrawerSection(title: "Reverb") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .reverbMix, title: "MIX")
                        DrawerKnob(id: .reverbSize)
                        DrawerKnob(id: .reverbDamping)
                        DrawerKnob(id: .reverbWidth)
                    }
                    .padding(.top, 26)
                }
                DrawerSection(title: "Compressor") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "GR %.0f dB", controller.meters.gainReduction))
                            .font(Nexora.Fonts.value(9))
                            .foregroundStyle(Nexora.Colors.turquoise)
                            .frame(height: 20)
                        HStack(spacing: 2) {
                            DrawerKnob(id: .compThreshold, title: "THRESH")
                            DrawerKnob(id: .compRatio)
                            DrawerKnob(id: .compAttack, title: "ATTACK")
                            DrawerKnob(id: .compRelease, title: "RELEASE")
                            DrawerKnob(id: .compMakeup)
                        }
                    }
                }
                DrawerSection(title: "Preset") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        HStack(spacing: 4) {
                            Button("Speichern") {
                                controller.saveEffectPreset(named: presetName)
                                presetName = ""
                            }
                            .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                            Menu("Laden") {
                                let _ = controller.presetRevision
                                ForEach(controller.presets.list(.effects)) { info in
                                    Button(info.name) { controller.loadEffectPreset(info) }
                                }
                            }
                            .frame(width: 70)
                        }
                        Button("FX zurücksetzen") { controller.updateMaster { $0 = MasterSettings() } }
                    }
                }
            }
        }
        .font(.system(size: 11))
    }
}
