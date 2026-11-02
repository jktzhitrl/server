import AppKit
import NexoraCore

/// Automatischer Screenshot-Modus für Dokumentation und CI:
/// `NEXORA Sampler.app/Contents/MacOS/NEXORA Sampler --screenshots <Ordner>`
///
/// Die App spielt das Demo-Pattern ab (ohne Audiogerät wird die Engine per Timer gerendert),
/// öffnet nacheinander alle Bereiche, speichert jeweils ein PNG des Fensters und beendet sich.
@MainActor
enum ScreenshotDirector {
    private static var started = false

    static func startIfRequested(_ controller: SamplerController) {
        let args = CommandLine.arguments
        guard !started, let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return }
        started = true
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        controller.screenshotMode = true
        controller.notice = nil
        Task { @MainActor in await run(controller, directory: dir) }
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func run(_ c: SamplerController, directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        c.startManualPump()

        var window: NSWindow?
        for _ in 0..<50 {
            window = NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") && !($0 is NSPanel) }
            if window != nil { break }
            await sleep(0.2)
        }
        guard let window else {
            print("[NEXORA] Screenshot: kein Fenster gefunden")
            NSApp.terminate(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)

        // Auf die Einrichtung der Werks-Bibliothek warten (max. 3 Minuten)
        for _ in 0..<360 where c.factoryInstallProgress != nil { await sleep(0.5) }

        func resize(_ height: CGFloat) async {
            window.setContentSize(NSSize(width: 1500, height: height))
            window.center()
            await sleep(0.6)
        }

        let body: CGFloat = 900
        let withDrawer: CGFloat = 1280

        // 1) Instrument, Demo läuft, mehrere Pads leuchten
        await resize(body)
        c.setXY(x: 0.62, y: 0.35)
        c.selectPad(1)
        c.play()
        await sleep(1.4)
        for pad in [0, 4, 9, 13] { c.host.send(.noteOn(pad: pad, velocity: 1)) }
        await sleep(0.12)
        capture(window, "01-instrument", into: directory)

        // 2) Sequencer
        await resize(withDrawer)
        c.drawer = .sequencer
        await sleep(1.0)
        capture(window, "02-sequencer", into: directory)

        // 3) Pad-Editor
        c.selectPad(0)
        c.drawer = .editor
        await sleep(0.8)
        capture(window, "03-pad-editor", into: directory)

        // 4) Sample-Browser mit Werks-Bibliothek
        c.drawer = .browser
        if let kicks = c.library.factoryCollections.first {
            c.library.selectedCollectionID = kicks.id
            c.library.selectedItemID = kicks.items.first?.id
        }
        await sleep(0.8)
        capture(window, "04-browser", into: directory)

        // 5) Master-Effekte
        c.drawer = .effects
        await sleep(0.8)
        capture(window, "05-effects", into: directory)

        // 6) Kits
        c.drawer = .kits
        await sleep(0.8)
        capture(window, "06-kits", into: directory)

        // 7) MIDI
        c.drawer = .midi
        await sleep(0.8)
        capture(window, "07-midi", into: directory)

        // 8) Sequencer-Modus auf den Pads
        c.drawer = nil
        await resize(body)
        c.selectPad(4)
        c.setPadMode(.step)
        await sleep(1.0)
        capture(window, "08-step-mode", into: directory)

        // 9) Keyboard-Modus
        c.selectPad(14)
        c.setPadMode(.keyboard)
        await sleep(0.6)
        capture(window, "09-keyboard-mode", into: directory)

        // 10) Alternatives Farbschema
        c.setPadMode(.play)
        UserDefaults.standard.set(NexoraTheme.lilac.rawValue, forKey: NexoraTheme.storageKey)
        await sleep(1.2)
        capture(window, "10-theme-lilac", into: directory)
        UserDefaults.standard.set(NexoraTheme.crimson.rawValue, forKey: NexoraTheme.storageKey)
        await sleep(0.3)

        // 11) Song & Motion
        await resize(withDrawer)
        c.songClear()
        for slot in [0, 0, 1, 0] { c.songAppend(slot) }
        c.setSongMode(true)
        let slot = c.project.sequencer.currentPattern
        for step in 0..<16 {
            c.project.sequencer.patterns[slot].recordMotion(parameter: .padCutoff, pad: 0, step: step, value: 300 * pow(50, Double(step) / 15))
            c.project.sequencer.patterns[slot].recordMotion(parameter: .reverbMix, pad: 0, step: step, value: Double(step % 8) / 10)
        }
        c.pushPattern(slot)
        c.drawer = .song
        await sleep(1.8)
        capture(window, "11-song-motion", into: directory)
        c.setSongMode(false)

        // 12) Sampling
        c.sampling.targetPad = 15
        c.drawer = .sampling
        await sleep(0.8)
        capture(window, "12-sampling", into: directory)

        // 13) 64 Schritte
        c.drawer = .sequencer
        c.setPatternLength(64)
        c.setStepPage(2, follow: true)
        await sleep(2.0)
        capture(window, "13-64-steps", into: directory)
        c.drawer = nil

        c.stop()
        c.isDirty = false
        print("[NEXORA] Screenshots gespeichert in \(directory.path)")
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, _ name: String, into directory: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = directory.appendingPathComponent(name + ".png")
        do {
            try data.write(to: url)
            print("[NEXORA] Screenshot \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        } catch {
            print("[NEXORA] Screenshot fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
