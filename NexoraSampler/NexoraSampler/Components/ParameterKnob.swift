import SwiftUI
import NexoraCore

/// Drehregler, der direkt an einen `ParameterID` gebunden ist.
/// Rechtsklick: MIDI-Learn, Mapping entfernen, Zuweisung an XY-Pad, Zurücksetzen.
struct ParameterKnob: View {
    @Environment(SamplerController.self) private var controller
    let id: ParameterID
    var title: String?
    /// Fester Pad-Bezug; `nil` = ausgewähltes Pad
    var pad: Int?
    var size: CGFloat = 38
    var labelColor: Color = Nexora.Colors.bodyLabel
    var style: KnobView.Style = .standard
    var showsValue = true

    var body: some View {
        let target = pad ?? controller.selectedPad
        let spec = id.spec
        KnobView(
            title: title ?? spec.shortName,
            value: controller.project.normalizedValue(of: id, pad: target),
            defaultValue: spec.defaultNormalized,
            valueText: spec.format(controller.project.value(of: id, pad: target)),
            size: size,
            style: style,
            labelColor: labelColor,
            showsValue: showsValue,
            isLearning: controller.midiLearnActive && controller.learnTarget == id,
            hasMapping: controller.project.midi.mapping(for: id) != nil,
            onChange: { controller.setParameter(id, normalized: $0, pad: pad) },
            onBegin: {
                if controller.midiLearnActive { controller.learnTarget = id }
                controller.showParameter(id, pad: target)
            }
        )
        .overlay(alignment: .topLeading) {
            if controller.hasMotion(id, pad: target) {
                Circle().fill(Nexora.Colors.pink).frame(width: 5, height: 5)
                    .shadow(color: Nexora.Colors.pink, radius: 3)
                    .help("Motion-Spur im aktuellen Pattern")
            }
        }
        .help("\(spec.name)\(id.isPadParameter ? " (Pad \(target + 1))" : "") – ziehen zum Ändern, ⌥ = fein, Doppelklick = Standardwert. Rechtsklick für MIDI-Learn und XY-Zuweisung.")
        .contextMenu {
            Button("MIDI-Learn") { controller.beginLearn(for: id) }
            if controller.project.midi.mapping(for: id) != nil {
                Button("MIDI-Zuordnung entfernen") { controller.removeMIDIMapping(for: id) }
            }
            Divider()
            Button("Auf XY-Pad X-Achse legen") { controller.assignXY(axis: .x, parameter: id) }
            Button("Auf XY-Pad Y-Achse legen") { controller.assignXY(axis: .y, parameter: id) }
            if controller.hasMotion(id, pad: target) {
                Divider()
                Button("Motion-Spur löschen") { controller.removeMotion(id, pad: target) }
            }
            Divider()
            Button("Zurücksetzen") { controller.setParameter(id, normalized: spec.defaultNormalized, pad: pad) }
        }
    }
}
