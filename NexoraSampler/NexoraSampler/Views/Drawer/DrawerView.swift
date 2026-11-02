import SwiftUI
import NexoraCore

/// Ausklappbarer, dunkler Bereich unter dem Instrument mit den erweiterten Funktionen.
struct DrawerView: View {
    @Environment(SamplerController.self) private var controller
    let panel: DrawerPanel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(DrawerPanel.allCases) { p in
                    Button {
                        controller.drawer = p
                    } label: {
                        Text(p.title)
                            .font(Nexora.Fonts.label(9))
                            .tracking(1)
                            .foregroundStyle(p == panel ? Nexora.Colors.display : Nexora.Colors.labelMuted)
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(p == panel ? Nexora.Colors.turquoise : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    controller.drawer = nil
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Nexora.Colors.labelMuted)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bereich schließen")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Nexora.Colors.panelLine).frame(height: 1)
            Group {
                switch panel {
                case .editor: PadEditorPanel()
                case .sequencer: SequencerPanel()
                case .song: SongMotionPanel()
                case .sampling: SamplingPanel()
                case .browser: SampleBrowserPanel()
                case .effects: EffectsPanel()
                case .kits: KitsPanel()
                case .midi: MIDIPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.panel, Nexora.Colors.panelDeep], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Nexora.Colors.panelLine, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        )
        .environment(\.colorScheme, .dark)
    }
}

/// Regler im Drawer (helle Beschriftung auf dunklem Grund).
struct DrawerKnob: View {
    let id: ParameterID
    var title: String?
    var pad: Int?

    var body: some View {
        ParameterKnob(id: id, title: title, pad: pad, size: 34, labelColor: Nexora.Colors.labelLight)
    }
}

/// Überschrift einer Gruppe im Drawer.
struct DrawerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        PanelSection(title: title, color: Nexora.Colors.labelMuted) {
            content
        }
    }
}
