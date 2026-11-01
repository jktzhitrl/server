import Foundation
import NexoraCore

extension SamplerController {
    /// Installiert beim ersten Start (bzw. nach einem Update der Klänge) die Werks-Bibliothek
    /// im Hintergrund in die Sample-Bibliothek.
    func installFactoryLibraryIfNeeded() {
        let lib = library.library
        guard !FactoryLibraryInstaller.isInstalled(in: lib) else { return }
        library.isBusy = true
        factoryInstallProgress = 0
        Task.detached(priority: .utility) { [weak self] in
            var failure: String?
            do {
                try FactoryLibraryInstaller.install(into: lib) { progress in
                    Task { @MainActor in self?.factoryInstallProgress = progress }
                }
            } catch {
                failure = error.localizedDescription
            }
            let message = failure
            await MainActor.run {
                guard let self else { return }
                self.factoryInstallProgress = nil
                self.library.isBusy = false
                self.library.reload()
                if let message {
                    self.report("Werks-Bibliothek", "Die Klangbibliothek konnte nicht vollständig eingerichtet werden: \(message)")
                } else {
                    self.showLCD("SOUND LIBRARY READY", "\(FactoryLibrary.sounds.count) SOUNDS IN BROWSER", seconds: 3)
                }
            }
        }
    }

    /// Lädt ein Werks-Kit (16 Klänge der Bibliothek) auf die Pads.
    func loadFactoryKit(_ kit: FactoryKitDefinition) {
        let ids = kit.soundIDs
        loadingPads = Set(0..<16)
        showLCD("LOADING KIT", kit.name.uppercased())
        Task.detached(priority: .userInitiated) { [weak self] in
            var buffers: [(Int, FactorySound, SampleBuffer)] = []
            for (pad, id) in ids.prefix(16).enumerated() {
                guard let sound = FactoryLibrary.sound(id: id) else { continue }
                buffers.append((pad, sound, sound.makeBuffer()))
            }
            let loaded = buffers
            await MainActor.run {
                guard let self else { return }
                for (pad, sound, buffer) in loaded {
                    let item = self.library.library.factoryItem(category: sound.category.rawValue, name: sound.name)
                    let fileURL = item.flatMap { self.library.url(for: $0) }
                    self.project.pads[pad].name = sound.name.uppercased()
                    self.project.pads[pad].settings = sound.settings
                    self.project.pads[pad].sample = SampleReference(fileName: sound.name + ".wav", libraryItemID: item?.id,
                                                                    frameCount: buffer.frameCount, sampleRate: buffer.sampleRate)
                    self.setPadSample(pad, buffer: buffer, fileURL: fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil })
                    self.host.send(.setPadSettings(pad: pad, settings: sound.settings))
                }
                self.project.kitName = kit.name
                self.loadingPads.removeAll()
                self.showLCD("KIT", kit.name.uppercased())
                self.markDirty()
            }
        }
    }

    // MARK: - Engine ohne Audiogerät antreiben (Screenshot-Modus)

    /// Rendert die Engine per Timer, z. B. auf Rechnern ohne Audioausgabe.
    /// Die Audio-Ausgabe muss vorher gestoppt sein (es darf nur ein Thread rendern).
    func startManualPump() {
        host.stop()
        let frames = Int(host.sampleRate / 30)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        pumpLeft = left
        pumpRight = right
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.host.sampler.render(frameCount: frames, left: left, right: right)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pumpTimer = t
    }
}
