import Foundation
import AppKit
import UniformTypeIdentifiers
import NexoraCore

extension SamplerController {
    // MARK: - Ungespeicherte Änderungen

    enum DiscardDecision { case save, discard, cancel }

    func askToSaveChanges() -> DiscardDecision {
        guard isDirty else { return .discard }
        let alert = NSAlert()
        alert.messageText = "Änderungen an „\(project.name)“ sichern?"
        alert.informativeText = "Nicht gesicherte Änderungen gehen sonst verloren."
        alert.addButton(withTitle: "Sichern")
        alert.addButton(withTitle: "Nicht sichern")
        alert.addButton(withTitle: "Abbrechen")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Fragt ggf. nach dem Sichern. Liefert `false`, wenn der Vorgang abgebrochen wurde.
    func confirmDiscardChanges() -> Bool {
        switch askToSaveChanges() {
        case .save: return saveProject()
        case .discard: return true
        case .cancel: return false
        }
    }

    // MARK: - Projekt

    func newProject() {
        guard confirmDiscardChanges() else { return }
        host.send(.transport(.stop))
        host.send(.allNotesOff)
        project = ProjectDocument(name: "Untitled")
        projectURL = nil
        isRecording = false
        loadFactoryKit(resetPatterns: true)
        isDirty = false
        showLCD("NEW PROJECT", FactoryKit.kitName.uppercased())
    }

    func openProjectWithPanel() {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.nexoraProject, .json]
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "NEXORA-Projekt (.nexora) öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url, askToSave: false)
    }

    func openProject(at url: URL, askToSave: Bool = true) {
        if askToSave { guard confirmDiscardChanges() else { return } }
        let packageURL = ProjectPackage.packageURL(for: url)
        let document: ProjectDocument
        do {
            document = try ProjectPackage.read(from: packageURL)
        } catch {
            report("Projekt konnte nicht geöffnet werden", error.localizedDescription)
            return
        }
        host.send(.transport(.stop))
        host.send(.allNotesOff)
        isRecording = false
        project = document
        projectURL = packageURL
        UserDefaults.standard.set(packageURL.path, forKey: PrefKey.lastProjectPath)
        NSDocumentController.shared.noteNewRecentDocumentURL(packageURL)
        for i in 0..<16 { setPadSample(i, buffer: nil, fileURL: nil) }
        pushFullState()
        loadPadSamples(for: document.pads, packageURL: packageURL) { [weak self] missing in
            guard let self else { return }
            self.isDirty = false
            if !missing.isEmpty {
                self.report("Fehlende Samples",
                            "Folgende Samples wurden nicht gefunden und können über den Sample-Browser neu zugewiesen werden:\n"
                            + missing.joined(separator: "\n"))
            }
        }
        showLCD("PROJECT", document.name.uppercased())
    }

    /// Dekodiert alle Pad-Samples eines Projekts/Kits im Hintergrund.
    func loadPadSamples(for pads: [PadConfig], packageURL: URL?, completion: @escaping ([String]) -> Void) {
        let resolver = makeResolver(extraSearch: packageURL.map { [$0.deletingLastPathComponent()] } ?? [])
        let jobs: [(Int, SampleReference, URL?)] = pads.compactMap { pad in
            guard let ref = pad.sample else { return nil }
            return (pad.index, ref, resolver.resolve(ref, packageURL: packageURL))
        }
        loadingPads = Set(jobs.map(\.0))
        Task.detached(priority: .userInitiated) { [weak self] in
            var results: [(Int, SampleBuffer?, URL?, String)] = []
            for (index, ref, url) in jobs {
                if let url, let buffer = try? AudioFileLoader.load(url: url, name: ref.fileName.isEmpty ? nil : URL(fileURLWithPath: ref.fileName).deletingPathExtension().lastPathComponent) {
                    results.append((index, buffer, url, ref.fileName))
                } else {
                    results.append((index, nil, nil, ref.fileName))
                }
            }
            let finished = results
            await MainActor.run { [weak self] in
                guard let self else { return }
                var missing: [String] = []
                for (index, buffer, url, name) in finished {
                    if let buffer {
                        self.setPadSample(index, buffer: buffer, fileURL: url)
                    } else {
                        missing.append(String(format: "Pad %02d: %@", index + 1, name))
                    }
                }
                self.loadingPads.removeAll()
                completion(missing)
            }
        }
    }

    func makeResolver(extraSearch: [URL] = []) -> SampleResolver {
        let lib = library
        var dirs = [library.root]
        dirs.append(contentsOf: extraSearch)
        if let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first { dirs.append(music) }
        let libraryURLs: [UUID: URL] = Dictionary(uniqueKeysWithValues: lib.collections.flatMap { c in
            c.items.compactMap { item in lib.url(for: item).map { (item.id, $0) } }
        })
        return SampleResolver(
            searchDirectories: dirs,
            bookmarkResolver: { data in
                var stale = false
                return try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            },
            libraryLookup: { libraryURLs[$0] }
        )
    }

    /// Quellen aller Pad-Samples für das Speichern.
    func currentSampleSources() -> [PadSampleSource] {
        (0..<16).map { i in
            if let url = padFileURLs[i], FileManager.default.fileExists(atPath: url.path) { return .file(url) }
            if let buffer = padSamples[i] { return .buffer(buffer) }
            return .none
        }
    }

    @discardableResult
    func saveProject() -> Bool {
        guard let url = projectURL else { return saveProjectAs() }
        return writeProject(to: url)
    }

    @discardableResult
    func saveProjectAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.nexoraProject]
        panel.nameFieldStringValue = project.name == "Untitled" ? "Mein Beat" : project.name
        panel.message = "Projekt inklusive aller Samples speichern"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        if url.pathExtension != ProjectPackage.fileExtension { url.appendPathExtension(ProjectPackage.fileExtension) }
        project.name = url.deletingPathExtension().lastPathComponent
        return writeProject(to: url)
    }

    private func writeProject(to url: URL) -> Bool {
        do {
            let saved = try ProjectPackage.write(project, sources: currentSampleSources(), to: url)
            project = saved
            projectURL = url
            // Künftige Speichervorgänge kopieren aus dem Paket selbst.
            for i in 0..<16 {
                if let rel = saved.pads[i].sample?.packagePath { padFileURLs[i] = url.appendingPathComponent(rel) }
            }
            isDirty = false
            UserDefaults.standard.set(url.path, forKey: PrefKey.lastProjectPath)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            showLCD("SAVED", project.name.uppercased())
            return true
        } catch {
            report("Speichern fehlgeschlagen", error.localizedDescription)
            return false
        }
    }

    // MARK: - Samples importieren

    func importSamplesWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Audiodateien in die Sample-Bibliothek importieren"
        guard panel.runModal() == .OK else { return }
        importToLibrary(panel.urls)
    }

    func importToLibrary(_ urls: [URL]) {
        let result = library.importFiles(urls, copy: AppPreferences.copyImportsToLibrary)
        if !result.imported.isEmpty {
            showLCD("IMPORTED", "\(result.imported.count) SAMPLE(S)")
            library.selectedItemID = result.imported.last?.id
        }
        if !result.failed.isEmpty {
            report("Import teilweise fehlgeschlagen", "Nicht importiert:\n" + result.failed.joined(separator: "\n"))
        }
        drawer = .browser
    }

    func loadLibraryItem(_ item: SampleLibraryItem, into pad: Int) {
        guard let url = library.url(for: item) else { return }
        loadSample(from: url, into: pad, libraryItemID: item.id)
    }

    // MARK: - Kits

    func saveKit(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try presets.saveKit(name: trimmed, pads: project.pads, sources: currentSampleSources())
            project.kitName = trimmed
            presetRevision += 1
            showLCD("KIT SAVED", trimmed.uppercased())
            markDirty()
        } catch {
            report("Kit konnte nicht gespeichert werden", error.localizedDescription)
        }
    }

    func loadKit(_ info: PresetInfo) {
        do {
            let kit = try presets.loadKit(at: info.url)
            for pad in kit.pads {
                project.pads[pad.index].name = pad.name
                project.pads[pad.index].settings = pad.settings
                project.pads[pad.index].sample = pad.sample
                project.pads[pad.index].keyboardKey = pad.keyboardKey.isEmpty ? PadConfig.defaultKey(for: pad.index) : pad.keyboardKey
                setPadSample(pad.index, buffer: nil, fileURL: nil)
                host.send(.setPadSettings(pad: pad.index, settings: pad.settings))
            }
            project.kitName = kit.name
            markDirty()
            loadPadSamples(for: kit.pads, packageURL: info.url) { [weak self] missing in
                if !missing.isEmpty {
                    self?.report("Fehlende Samples im Kit", missing.joined(separator: "\n"))
                }
            }
            showLCD("KIT", kit.name.uppercased())
        } catch {
            report("Kit konnte nicht geladen werden", error.localizedDescription)
        }
    }

    func clearAllPads() {
        for i in 0..<16 {
            setPadSample(i, buffer: nil, fileURL: nil)
            project.pads[i] = PadConfig(index: i, name: "PAD \(i + 1)", keyboardKey: project.pads[i].keyboardKey)
            host.send(.setPadSettings(pad: i, settings: project.pads[i].settings))
        }
        project.kitName = "Empty Kit"
        showLCD("KIT", "CLEARED")
        markDirty()
    }

    func deletePreset(_ info: PresetInfo) {
        do {
            try presets.delete(info)
            presetRevision += 1
        } catch {
            report("Löschen fehlgeschlagen", error.localizedDescription)
        }
    }

    // MARK: - Effekt- und Pattern-Presets

    func saveEffectPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try presets.saveEffects(name: trimmed, master: project.master)
            presetRevision += 1
            showLCD("FX PRESET SAVED", trimmed.uppercased())
        } catch {
            report("Preset konnte nicht gespeichert werden", error.localizedDescription)
        }
    }

    func loadEffectPreset(_ info: PresetInfo) {
        do {
            let preset = try presets.loadEffects(at: info.url)
            updateMaster { $0 = preset.master }
            showLCD("FX PRESET", preset.name.uppercased())
        } catch {
            report("Preset konnte nicht geladen werden", error.localizedDescription)
        }
    }

    func savePatternPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try presets.savePattern(name: trimmed, pattern: currentPattern, bpm: project.bpm, swing: project.swing)
            presetRevision += 1
            showLCD("PATTERN SAVED", trimmed.uppercased())
        } catch {
            report("Pattern konnte nicht gespeichert werden", error.localizedDescription)
        }
    }

    func loadPatternPreset(_ info: PresetInfo, applyTempo: Bool) {
        do {
            let preset = try presets.loadPattern(at: info.url)
            let slot = project.sequencer.currentPattern
            var p = preset.pattern
            p.id = UUID()
            project.sequencer.patterns[slot] = p
            pushPattern(slot)
            if applyTempo {
                project.bpm = preset.bpm
                project.swing = preset.swing
                host.send(.setTempo(bpm: project.bpm, swing: project.swing))
            }
            showLCD("PATTERN \(SequencerState.slotName(slot))", preset.name.uppercased())
            markDirty()
        } catch {
            report("Pattern konnte nicht geladen werden", error.localizedDescription)
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
