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

        // 1) Instrument, Demo läuft, mehrere Pads leuchten
        await resize(840)
        c.setXY(x: 0.62, y: 0.35)
        c.selectPad(1)
        c.play()
        await sleep(1.4)
        for pad in [0, 4, 9, 13] { c.host.send(.noteOn(pad: pad, velocity: 1)) }
        await sleep(0.12)
        capture(window, "01-instrument", into: directory)

        // 2) Sequencer
        await resize(1180)
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

        // 8) Step-Modus
        c.drawer = nil
        await resize(840)
        c.selectPad(4)
        c.padMode = .step
        await sleep(1.0)
        capture(window, "08-step-mode", into: directory)

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
