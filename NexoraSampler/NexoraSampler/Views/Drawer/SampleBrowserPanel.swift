import SwiftUI
import NexoraCore

/// Sample-Browser: eigene Bibliotheken, Import (auch per Drag & Drop aus dem Finder),
/// Vorhören, Umbenennen, Entfernen und Ziehen auf die Pads.
struct SampleBrowserPanel: View {
    @Environment(SamplerController.self) private var controller
    @State private var newCollectionName = ""
    @State private var renamingItem: UUID?
    @State private var renameDraft = ""
    @State private var renamingCollection = false
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var library = controller.library
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                PanelLabel(text: "Bibliotheken", color: Nexora.Colors.labelMuted, size: 8)
                List(selection: $library.selectedCollectionID) {
                    ForEach(library.collections) { collection in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Nexora.Colors.turquoise)
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.items.count)").foregroundStyle(.secondary)
                        }
                        .tag(collection.id)
                    }
                }
                .frame(width: 210, height: 170)
                HStack(spacing: 4) {
                    TextField("Neue Bibliothek", text: $newCollectionName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        createCollection()
                    } label: { Image(systemName: "plus") }
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Bibliothek anlegen")
                }
                .frame(width: 210)
                HStack(spacing: 4) {
                    Button("Umbenennen") {
                        renameDraft = library.selectedCollection?.name ?? ""
                        renamingCollection = true
                    }
                    Button("Löschen", role: .destructive) {
                        if let id = library.selectedCollection?.id { attempt { try library.removeCollection(id) } }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Suchen", text: $library.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Button("Importieren …") { controller.importSamplesWithPanel() }
                        .help("Audiodateien in die ausgewählte Bibliothek importieren (⌘I)")
                    Button("Auf Pad \(controller.selectedPad + 1) laden") { loadSelected() }
                        .disabled(selectedItem == nil)
                    Button("Vorhören") { previewSelected() }
                        .disabled(selectedItem == nil)
                    Button("Stopp") { controller.stopPreview() }
                    Spacer()
                    Text(controller.libraryCopyHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                List(selection: $library.selectedItemID) {
                    ForEach(library.visibleItems) { item in
                        row(item)
                            .tag(item.id)
                            .draggable(controller.library.url(for: item) ?? URL(fileURLWithPath: "/"))
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let item = controller.library.visibleItems.first(where: { $0.id == id }) {
                        Button("Vorhören") { preview(item) }
                        Button("Auf ausgewähltes Pad laden") { controller.loadLibraryItem(item, into: controller.selectedPad) }
                        Button("Umbenennen") {
                            renameDraft = item.name
                            renamingItem = item.id
                        }
                        if let url = controller.library.url(for: item) {
                            Button("Im Finder zeigen") { controller.revealInFinder(url) }
                        }
                        Divider()
                        Button("Entfernen", role: .destructive) {
                            attempt { try controller.library.removeItem(item.id) }
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let item = controller.library.visibleItems.first(where: { $0.id == id }) {
                        controller.loadLibraryItem(item, into: controller.selectedPad)
                    }
                }
                .overlay(alignment: .center) {
                    if library.visibleItems.isEmpty {
                        Text("Audiodateien aus dem Finder hierher ziehen oder „Importieren …“ wählen")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dropTargeted ? Nexora.Colors.pink : Color.clear, lineWidth: 2))
                .dropDestination(for: URL.self) { urls, _ in
                    controller.importToLibrary(urls)
                    return true
                } isTargeted: { dropTargeted = $0 }
                .onChange(of: library.selectedItemID) { _, newValue in
                    if AppPreferences.autoPreview, let id = newValue, let item = controller.library.visibleItems.first(where: { $0.id == id }) {
                        preview(item)
                    }
                }
                Text("Tipp: Einträge auf ein Pad ziehen, um sie zu laden. Doppelklick lädt auf das ausgewählte Pad.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .alert("Umbenennen", isPresented: Binding(get: { renamingItem != nil || renamingCollection },
                                                   set: { if !$0 { renamingItem = nil; renamingCollection = false } })) {
            TextField("Name", text: $renameDraft)
            Button("OK") { commitRename() }
            Button("Abbrechen", role: .cancel) { renamingItem = nil; renamingCollection = false }
        }
    }

    private var selectedItem: LibraryItem? {
        guard let id = controller.library.selectedItemID else { return nil }
        return controller.library.visibleItems.first { $0.id == id }
    }

    private func row(_ item: LibraryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(Nexora.Colors.turquoise)
            Text(item.name).lineLimit(1)
            Spacer()
            Text(item.fileExtension.uppercased()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Text(String(format: "%.1f kHz", item.sampleRate / 1000)).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            Text(item.channels == 1 ? "Mono" : "Stereo").foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
            Text(String(format: "%.2f s", item.duration)).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func preview(_ item: LibraryItem) {
        guard let url = controller.library.url(for: item) else { return }
        controller.preview(url: url)
    }

    private func previewSelected() {
        if let item = selectedItem { preview(item) }
    }

    private func loadSelected() {
        if let item = selectedItem { controller.loadLibraryItem(item, into: controller.selectedPad) }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        attempt { try controller.library.createCollection(named: name) }
        newCollectionName = ""
    }

    private func commitRename() {
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let id = renamingItem {
            attempt { try controller.library.renameItem(id, to: name) }
        } else if renamingCollection, let id = controller.library.selectedCollection?.id {
            attempt { try controller.library.renameCollection(id, to: name) }
        }
        renamingItem = nil
        renamingCollection = false
    }

    private func attempt(_ body: () throws -> Void) {
        do { try body() } catch { controller.report("Bibliothek", error.localizedDescription) }
    }
}

extension SamplerController {
    var libraryCopyHint: String {
        AppPreferences.copyImportsToLibrary ? "Importe werden in die Bibliothek kopiert" : "Importe werden nur referenziert"
    }
}
