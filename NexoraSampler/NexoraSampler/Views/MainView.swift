import SwiftUI
import NexoraCore

/// Wurzelansicht: Instrumentengehäuse + ausklappbarer Bereich. Das gesamte Layout wird
/// proportional skaliert, damit das Instrument in jeder Fenstergröße vollständig sichtbar bleibt.
struct MainView: View {
    @Environment(SamplerController.self) private var controller
    @AppStorage(NexoraTheme.storageKey) private var themeRaw = NexoraTheme.crimson.rawValue

    var body: some View {
        @Bindable var controller = controller
        let _ = { Nexora.theme = NexoraTheme(rawValue: themeRaw) ?? .crimson }()
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
            .id(themeRaw)
        }
        .background(
            LinearGradient(colors: [Color(hex: 0x1E1A20), Color(hex: 0x0E0C10)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.22), value: controller.drawer)
        .navigationTitle(controller.project.name + (controller.isDirty ? " •" : ""))
        .alert(item: $controller.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $controller.showSliceSheet) {
            SliceSheet().environment(controller)
        }
        .sheet(isPresented: $controller.showExportSheet) {
            ExportSheet()
                .environment(controller)
        }
    }
}
