import SwiftUI
import NexoraCore

/// Pad-Editor: Sample-Bereich mit Wellenform, Wiedergabe, Hüllkurve, Filter, LFO und Pad-Effekte.
struct PadEditorPanel: View {
    @Environment(SamplerController.self) private var controller
    @State private var nameDraft = ""

    var body: some View {
        let pad = controller.selectedPad
        let config = controller.project.pads[pad]
        let s = config.settings
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(String(format: "PAD %02d", pad + 1))
                        .font(Nexora.Fonts.lcd(13))
                        .foregroundStyle(Nexora.Colors.turquoise)
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit { controller.renamePad(pad, to: nameDraft) }
                        .help("Pad-Namen ändern (Enter bestätigt)")
                    Button("Laden …") { controller.chooseSampleForSelectedPad() }
                        .help("Audiodatei auf dieses Pad laden (⌘L)")
                    Button("Leeren") { controller.clearPad(pad) }
                    Button("Slice …") { controller.showSliceSheet = true }
                        .help("Sample in Stücke zerlegen und auf Pads verteilen")
                        .disabled(controller.padSamples[pad] == nil)
                    Button {
                        controller.padDown(pad, velocity: 1)
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            controller.padUp(pad)
                        }
                    } label: { Image(systemName: "play.fill") }
                        .help("Pad anspielen")
                }
                SampleRegionEditor(pad: pad)
                    .frame(width: 430, height: 120)
                HStack(spacing: 14) {
                    labeledPicker("Modus", PlayMode.allCases, s.playMode, { $0.shortName }) { v in controller.updatePad(pad) { $0.settings.playMode = v } }
                    labeledPicker("Pitch", PitchMode.allCases, s.pitchMode, { $0.shortName }) { v in controller.updatePad(pad) { $0.settings.pitchMode = v } }
                }
                HStack(spacing: 14) {
                    Toggle("Reverse", isOn: Binding(get: { s.reverse }, set: { v in controller.updatePad(pad) { $0.settings.reverse = v } }))
                    Toggle("Mono", isOn: Binding(get: { s.mono }, set: { v in controller.updatePad(pad) { $0.settings.mono = v } }))
                        .help("Neuer Anschlag beendet die vorherige Stimme dieses Pads")
                    Stepper("Choke \(s.chokeGroup == 0 ? "–" : "\(s.chokeGroup)")", value: Binding(
                        get: { s.chokeGroup }, set: { v in controller.updatePad(pad) { $0.settings.chokeGroup = min(max(v, 0), 8) } }), in: 0...8)
                        .help("Pads derselben Choke-Gruppe schneiden sich gegenseitig ab (z. B. offene/geschlossene Hi-Hat)")
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                HStack(spacing: 14) {
                    TextField("Taste", text: Binding(get: { config.keyboardKey.uppercased() }, set: { controller.setPadKey(pad, key: $0) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 44)
                        .help("Tastaturtaste zum Auslösen")
                    Text("MIDI \(SamplerController.noteName(controller.project.midi.padNotes[pad]))")
                        .font(Nexora.Fonts.value(10))
                    Button(controller.noteLearnPad == pad ? "Warte auf Note …" : "Note lernen") {
                        controller.noteLearnPad = controller.noteLearnPad == pad ? nil : pad
                    }
                }
                .font(.system(size: 11))
            }
            .frame(width: 440, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                DrawerSection(title: "Tune · Level") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .padPitch)
                        DrawerKnob(id: .padFineTune)
                        DrawerKnob(id: .padSpeed)
                        DrawerKnob(id: .padVolume)
                        DrawerKnob(id: .padPan)
                        DrawerKnob(id: .padVelocitySensitivity)
                    }
                }
                DrawerSection(title: "Envelope") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .padAttack)
                        DrawerKnob(id: .padDecay)
                        DrawerKnob(id: .padSustain)
                        DrawerKnob(id: .padRelease)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                DrawerSection(title: "Pad Filter · LFO") {
                    HStack(spacing: 2) {
                        VStack(spacing: 6) {
                            SegmentPicker(options: FilterMode.allCases, selection: s.filterMode, title: { $0.shortName }) { v in
                                controller.updatePad(pad) { $0.settings.filterMode = v }
                            }
                            HStack(spacing: 2) {
                                DrawerKnob(id: .padCutoff)
                                DrawerKnob(id: .padResonance)
                            }
                        }
                        VStack(spacing: 6) {
                            SegmentPicker(options: PadLFOTarget.allCases, selection: s.lfoTarget, title: { $0.shortName }) { v in
                                controller.updatePad(pad) { $0.settings.lfoTarget = v }
                            }
                            HStack(spacing: 2) {
                                DrawerKnob(id: .padLFORate)
                                DrawerKnob(id: .padLFODepth)
                                SelectorButton(caption: "Shape", value: s.lfoShape.shortName, width: 36) {
                                    controller.updatePad(pad) { $0.settings.lfoShape = $0.settings.lfoShape.next }
                                }
                            }
                        }
                    }
                }
                DrawerSection(title: "Pad FX · Sends") {
                    HStack(spacing: 2) {
                        DrawerKnob(id: .padDrive)
                        DrawerKnob(id: .padCrushBits)
                        DrawerKnob(id: .padCrushRate)
                        DrawerKnob(id: .padReverbSend)
                        DrawerKnob(id: .padDelaySend)
                    }
                }
            }
        }
        .onAppear { nameDraft = config.name }
        .onChange(of: pad) { _, _ in nameDraft = controller.project.pads[controller.selectedPad].name }
        .onChange(of: config.name) { _, newValue in nameDraft = newValue }
    }

    private func labeledPicker<T: Hashable>(_ label: String, _ options: [T], _ selection: T, _ title: @escaping (T) -> String,
                                             _ onSelect: @escaping (T) -> Void) -> some View {
        HStack(spacing: 6) {
            PanelLabel(text: label, color: Nexora.Colors.labelMuted, size: 8)
            SegmentPicker(options: options, selection: selection, title: title, onSelect: onSelect)
        }
    }
}

/// Wellenform mit ziehbaren Start-/Endmarkern.
struct SampleRegionEditor: View {
    @Environment(SamplerController.self) private var controller
    let pad: Int
    @State private var draggingMarker: ParameterID?

    var body: some View {
        let s = controller.project.pads[pad].settings
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Nexora.Colors.display)
                if controller.padWaveforms[pad].isEmpty {
                    Text("Audiodatei hierher ziehen oder „Laden …“")
                        .font(Nexora.Fonts.value(10))
                        .foregroundStyle(Nexora.Colors.labelMuted)
                } else {
                    WaveformView(peaks: controller.padWaveforms[pad], start: s.start, end: s.end, reverse: s.reverse)
                        .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pos = min(max(value.location.x / geo.size.width, 0), 1)
                        if draggingMarker == nil {
                            draggingMarker = abs(pos - s.start) <= abs(pos - s.end) ? .padStart : .padEnd
                        }
                        if let marker = draggingMarker {
                            controller.setParameterValue(marker, value: pos, pad: pad)
                        }
                    }
                    .onEnded { _ in draggingMarker = nil }
            )
            .dropDestination(for: URL.self) { urls, _ in controller.handleDrop(urls, onPad: pad) }
        }
        .help("Start- und Endmarker ziehen. Audiodateien können direkt hierher gezogen werden.")
    }
}
