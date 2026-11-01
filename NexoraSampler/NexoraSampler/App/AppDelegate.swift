import AppKit

/// Behandelt App-Lebenszyklus: Sicherheitsabfrage beim Beenden, Öffnen von Projekten aus dem Finder.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: SamplerController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        return controller.confirmDiscardChanges() ? .terminateNow : .terminateCancel
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let controller {
            controller.openProject(at: url)
        } else {
            pendingURLs = urls
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let url = self.pendingURLs.first else { return }
                self.pendingURLs.removeAll()
                MainActor.assumeIsolated { self.controller?.openProject(at: url) }
            }
        }
    }
}
