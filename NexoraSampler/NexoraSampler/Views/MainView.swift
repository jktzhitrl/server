import SwiftUI
import NexoraCore

/// Wurzelansicht: Instrumentengehäuse + ausklappbarer Bereich. Das gesamte Layout wird
/// proportional skaliert, damit das Instrument in jeder Fenstergröße vollständig sichtbar bleibt.
struct MainView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        GeometryReader { geo in
            let drawerOpen = controller.drawer != nil
            let designWidth = Nexora.Metrics.designWidth + 40
            let designHeight = Nexora.Metrics.bodyHeight + 40 + (drawerOpen ? Nexora.Metrics.drawerHeight + 14 : 0)
            let scale = max(0.4, min(geo.size.width / designWidth, geo.size.height / designHeight))
            VStack(spacing: 14) {
                InstrumentBodyView()
                if let panel = controller.drawer {
                    DrawerView(panel: panel)
                        .frame(width: Nexora.Metrics.designWidth, height: Nexora.Metrics.drawerHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(20)
            .frame(width: designWidth, height: designHeight, alignment: .top)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(
            LinearGradient(colors: [Color(hex: 0x1C1530), Color(hex: 0x0F0B1A)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.22), value: controller.drawer)
        .navigationTitle(controller.project.name + (controller.isDirty ? " •" : ""))
        .alert(item: $controller.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $controller.showExportSheet) {
            ExportSheet()
                .environment(controller)
        }
    }
}

/// Das lilafarbene Gehäuse mit allen Bedienelementen.
struct InstrumentBodyView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Nexora.Colors.bodyTop, Nexora.Colors.bodyBottom], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Nexora.Colors.bodyEdge], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)
            ScrewsView()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        LCDDisplayView()
                            .frame(width: 320, height: 156)
                        FunctionButtonsView()
                    }
                    .frame(width: 320, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        BrandHeaderView()
                        KnobBankView()
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    XYPadView()
                        .frame(width: 320, height: 322)
                    PadGridView()
                        .frame(width: 330, height: 322)
                    TransportSectionView()
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .frame(width: Nexora.Metrics.designWidth, height: Nexora.Metrics.bodyHeight)
    }
}

/// Dezente Gehäuseschrauben in den Ecken.
private struct ScrewsView: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { i in
                let x: CGFloat = i % 2 == 0 ? 11 : geo.size.width - 11
                let y: CGFloat = i < 2 ? 11 : geo.size.height - 11
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.7), Nexora.Colors.bodyEdge], center: .topLeading, startRadius: 0, endRadius: 6))
                    .frame(width: 7, height: 7)
                    .overlay(Rectangle().fill(Nexora.Colors.bodyEdge).frame(width: 5, height: 1).rotationEffect(.degrees(Double(i) * 35)))
                    .position(x: x, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Schriftzug "NEXORA sampler" oben rechts mit Statusanzeigen.
struct BrandHeaderView: View {
    @Environment(SamplerController.self) private var controller

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                LEDView(isOn: controller.meters.midiActivity, color: Nexora.Colors.turquoise, size: 6)
                PanelLabel(text: "MIDI", size: 8)
                LEDView(isOn: controller.isRecording, color: Nexora.Colors.pink, size: 6)
                PanelLabel(text: "REC", size: 8)
                LEDView(isOn: controller.meters.transport == .playing, color: Nexora.Colors.turquoise, size: 6)
                PanelLabel(text: "RUN", size: 8)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("NEXORA")
                    .font(Nexora.Fonts.brand(30))
                    .tracking(3)
                    .foregroundStyle(LinearGradient(colors: [Nexora.Colors.labelDark, Color(hex: 0x4E3A86)], startPoint: .top, endPoint: .bottom))
                Text("sampler")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .italic()
                    .foregroundStyle(Nexora.Colors.labelDark.opacity(0.85))
            }
            .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
        }
        .frame(height: 34)
    }
}
