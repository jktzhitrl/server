import SwiftUI
import NexoraCore

/// Drum-Kits (Pad-Belegungen inkl. Samples und Einstellungen) sowie Preset-Verwaltung.
struct KitsPanel: View {
    @Environment(SamplerController.self) private var controller
    @State private var kitName = ""
    @State private var selectedKit: URL?

    var body: some View {
        let _ = controller.presetRevision
        let kits = controller.presets.list(.kit)
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel(text: "Gespeicherte Kits", color: Nexora.Colors.labelMuted, size: 8)
                List(selection: $selectedKit) {
                    ForEach(kits) { info in
                        HStack {
                            Image(systemName: "square.grid.4x3.fill").foregroundStyle(Nexora.Colors.pink)
                            Text(info.name)
                            Spacer()
                            Text(info.modified, style: .date).foregroundStyle(.secondary)
                        }
                        .tag(info.url)
                    }
                }
                .contextMenu(forSelectionType: URL.self) { urls in
                    if let url = urls.first, let info = kits.first(where: { $0.url == url }) {
                        Button("Laden") { controller.loadKit(info) }
                        Button("Im Finder zeigen") { controller.revealInFinder(info.url) }
                        Divider()
                        Button("Löschen", role: .destructive) { controller.deletePreset(info) }
                    }
                } primaryAction: { urls in
                    if let url = urls.first, let info = kits.first(where: { $0.url == url }) { controller.loadKit(info) }
                }
                .frame(width: 380, height: 210)
                HStack(spacing: 6) {
                    Button("Laden") {
                        if let url = selectedKit, let info = kits.first(where: { $0.url == url }) { controller.loadKit(info) }
                    }
                    .disabled(selectedKit == nil)
                    Button("Löschen", role: .destructive) {
                        if let url = selectedKit, let info = kits.first(where: { $0.url == url }) { controller.deletePreset(info) }
                        selectedKit = nil
                    }
                    .disabled(selectedKit == nil)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                DrawerSection(title: "Aktuelles Kit: \(controller.project.kitName)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TextField("Kit-Name", text: $kitName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                            Button("Als Kit speichern") {
                                controller.saveKit(named: kitName)
                                kitName = ""
                            }
                            .disabled(kitName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text("Ein Kit enthält alle 16 Pad-Belegungen mit Kopien der Samples, Namen, Tasten und Pad-Einstellungen.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 330, alignment: .leading)
                    }
                }
                DrawerSection(title: "Werks-Kits") {
                    VStack(alignment: .leading, spacing: 6) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(118), spacing: 6), count: 4), alignment: .leading, spacing: 6) {
                            factoryKitButton("NEXORA Factory") { controller.loadFactoryKit(resetPatterns: false) }
                            ForEach(FactoryLibrary.kits, id: \.name) { kit in
                                factoryKitButton(kit.name) { controller.loadFactoryKit(kit) }
                            }
                        }
                        HStack(spacing: 6) {
                            Button("Factory + Demo-Patterns") { controller.loadFactoryKit(resetPatterns: true) }
                            Button("Alle Pads leeren", role: .destructive) { controller.clearAllPads() }
                        }
                    }
                }
                DrawerSection(title: "Presets-Ordner") {
                    HStack(spacing: 6) {
                        Button("Im Finder zeigen") { controller.revealInFinder(controller.presets.root) }
                        Text(controller.presets.root.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 320, alignment: .leading)
                    }
                }
            }
        }
        .font(.system(size: 11))
    }

    private func factoryKitButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.4x3.fill").foregroundStyle(Nexora.Colors.pink)
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(width: 118, height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(Nexora.Colors.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(controller.project.kitName == name ? Nexora.Colors.turquoise : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Werks-Kit „\(name)“ auf die 16 Pads laden (Patterns bleiben erhalten)")
    }
}
