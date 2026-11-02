import SwiftUI
import NexoraCore

/// Song-Modus (Pattern-Kette) und Motion-Sequenz (aufgezeichnete Reglerbewegungen).
struct SongMotionPanel: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            songSection.frame(width: 520, alignment: .topLeading)
            motionSection.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 11))
    }

    // MARK: Song

    private var songSection: some View {
        let chain = controller.project.patternChain
        let songOn = controller.project.sequencer.songMode
        let playing = controller.meters.transport != .stopped
        return DrawerSection(title: "Song") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Song-Modus: Patterns laufen in dieser Reihenfolge",
                       isOn: Binding(get: { songOn }, set: { controller.setSongMode($0) }))
                    .toggleStyle(.checkbox)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 3), count: 15), alignment: .leading, spacing: 3) {
                        ForEach(Array(chain.enumerated()), id: \.offset) { index, slot in
                            let active = songOn && playing && controller.meters.songIndex == index
                            VStack(spacing: 0) {
                                Text("\(index + 1)").font(Nexora.Fonts.value(7))
                                    .foregroundStyle(active ? Nexora.Colors.display : Nexora.Colors.labelMuted)
                                Text(SequencerState.slotName(slot)).font(Nexora.Fonts.value(11).bold())
                                    .foregroundStyle(active ? Nexora.Colors.display : Nexora.Colors.labelLight)
                            }
                            .frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 4).fill(active ? Nexora.Colors.pink : Nexora.Colors.panel))
                            .contentShape(Rectangle())
                            .onTapGesture { controller.songSetEntry(index, slot: (slot + 1) % SequencerState.patternSlots) }
                            .contextMenu {
                                Button("◀ Nach vorn") { controller.songMove(index, by: -1) }
                                Button("Nach hinten ▶") { controller.songMove(index, by: 1) }
                                Divider()
                                ForEach(0..<SequencerState.patternSlots, id: \.self) { s in
                                    Button("Pattern \(SequencerState.slotName(s))") { controller.songSetEntry(index, slot: s) }
                                }
                                Divider()
                                Button("Entfernen") { controller.songRemove(at: index) }
                            }
                            .help("Klick: Pattern ändern · Rechtsklick: verschieben oder entfernen")
                        }
                    }
                    .padding(4)
                    if chain.isEmpty {
                        Text("Noch leer – unten Patterns anhängen.").foregroundStyle(Nexora.Colors.labelMuted).padding(6)
                    }
                }
                .frame(height: 70)
                .background(RoundedRectangle(cornerRadius: 6).fill(Nexora.Colors.panelDeep))
                HStack(spacing: 2) {
                    ForEach(0..<SequencerState.patternSlots, id: \.self) { slot in
                        Button("+\(SequencerState.slotName(slot))") { controller.songAppend(slot) }
                            .buttonStyle(.plain)
                            .font(Nexora.Fonts.value(9))
                            .frame(width: 30, height: 20)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Nexora.Colors.panel))
                            .help("Pattern \(SequencerState.slotName(slot)) an die Kette anhängen")
                    }
                }
                HStack(spacing: 8) {
                    Button("Letzten entfernen") { controller.songRemove(at: chain.count - 1) }.disabled(chain.isEmpty)
                    Button("Leeren") { controller.songClear() }.disabled(chain.isEmpty)
                    let secs = controller.songDuration
                    Text("\(chain.count)/64 Einträge · \(Int(secs) / 60):\(String(format: "%02d", Int(secs.rounded()) % 60)) min")
                        .foregroundStyle(Nexora.Colors.labelMuted)
                }
                Text("Klick auf einen Eintrag wechselt das Pattern, Rechtsklick verschiebt oder entfernt. Die Kette wird auch beim Export „Pattern-Kette“ verwendet. Am Ende beginnt der Song von vorn.")
                    .foregroundStyle(Nexora.Colors.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Motion

    private var motionSection: some View {
        let pattern = controller.currentPattern
        let slot = SequencerState.slotName(controller.project.sequencer.currentPattern)
        return DrawerSection(title: "Motion · Pattern \(slot) (\(pattern.motion.count)/\(MotionLane.maxLanes))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Wiedergabe").foregroundStyle(Nexora.Colors.labelMuted)
                    Picker("", selection: Binding(get: { controller.project.sequencer.motionMode }, set: { controller.setMotionMode($0) })) {
                        ForEach(MotionMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    Button("Alle löschen") { controller.clearMotion() }.disabled(pattern.motion.isEmpty)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if pattern.motion.isEmpty {
                            Text("Keine Motion-Spuren in diesem Pattern.").foregroundStyle(Nexora.Colors.labelMuted)
                        }
                        ForEach(Array(pattern.motion.enumerated()), id: \.offset) { index, lane in
                            HStack(spacing: 8) {
                                Text(lane.displayName).font(Nexora.Fonts.value(9)).frame(width: 128, alignment: .leading).lineLimit(1)
                                MotionBars(lane: lane, length: pattern.length)
                                Button("×") { controller.removeMotionLane(at: index) }.help("Spur löschen")
                            }
                            .frame(height: 24)
                        }
                    }
                }
                .frame(maxHeight: 170)
                Text("Aufnehmen: ● (REC) und ▶ drücken, dann Regler, XY-Pad oder MIDI-Controller bewegen. Die Bewegung wird pro Schritt gespeichert und bei jedem Durchlauf wiederholt. Regler mit Motion-Spur zeigen einen rosa Punkt.")
                    .foregroundStyle(Nexora.Colors.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Balkendarstellung einer Motion-Spur.
private struct MotionBars: View {
    let lane: MotionLane
    let length: Int

    var body: some View {
        let spec = lane.parameter.spec
        Canvas { context, size in
            let n = max(length, 1)
            let w = size.width / CGFloat(n)
            for s in 0..<n {
                guard let v = lane.values[s] else {
                    context.fill(Path(CGRect(x: CGFloat(s) * w, y: size.height - 1, width: max(w - 1, 1), height: 1)),
                                 with: .color(Nexora.Colors.pink.opacity(0.25)))
                    continue
                }
                let t = spec.normalized(fromValue: v)
                let h = max(2, CGFloat(t) * (size.height - 2))
                context.fill(Path(CGRect(x: CGFloat(s) * w, y: size.height - h, width: max(w - 1, 1), height: h)),
                             with: .color(Nexora.Colors.pink))
            }
        }
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 3).fill(Nexora.Colors.panelDeep))
    }
}
