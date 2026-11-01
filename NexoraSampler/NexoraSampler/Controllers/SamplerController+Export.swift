import Foundation
import AppKit
import UniformTypeIdentifiers
import NexoraCore

extension SamplerController {
    /// Exportiert das aktuelle Pattern bzw. die Pattern-Kette als WAV/AIFF.
    /// Gerendert wird offline mit derselben DSP-Engine wie bei der Live-Wiedergabe.
    func exportAudio(with settings: ExportSettings) {
        project.export = settings
        markDirty()
        let panel = NSSavePanel()
        let type: UTType = settings.format == .wav ? .wav : .aiff
        panel.allowedContentTypes = [type]
        let slotName = SequencerState.slotName(project.sequencer.currentPattern)
        panel.nameFieldStringValue = "\(project.name) - \(settings.exportChain ? "Chain" : "Pattern \(slotName)")"
        panel.message = "Audio exportieren"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != settings.format.fileExtension &&
            !(settings.format == .aiff && url.pathExtension.lowercased() == "aiff") {
            url.appendPathExtension(settings.format.fileExtension)
        }
        let order = settings.exportChain ? project.patternChain : [project.sequencer.currentPattern]
        let request = OfflineRenderer.Request(sampleRate: settings.sampleRate, document: project, samples: padSamples,
                                              patternOrder: order, loops: settings.loops, tailSeconds: settings.tailSeconds)
        exportCancellation.reset()
        exportProgress = 0
        let flag = exportCancellation
        let progressHandler: @Sendable (Double) -> Bool = { [weak self] value in
            Task { @MainActor in self?.exportProgress = value }
            return !flag.isCancelled
        }
        let destination = url
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                var result = try OfflineRenderer.render(request, progress: progressHandler)
                if settings.normalize { OfflineRenderer.normalize(&result) }
                try AudioFileWriter.write(left: result.left, right: result.right, sampleRate: result.sampleRate,
                                          format: settings.format, bitDepth: settings.bitDepth, to: destination)
                let duration = result.duration
                await self?.exportFinished(url: destination, duration: duration)
            } catch is OfflineRenderer.Cancelled {
                await self?.exportCancelled()
            } catch {
                await self?.exportFailed(error)
            }
        }
    }

    func cancelExport() {
        exportCancellation.cancel()
    }

    private func exportFinished(url: URL, duration: Double) {
        exportProgress = nil
        showExportSheet = false
        showLCD("EXPORTED", String(format: "%@ %.1fs", url.lastPathComponent.uppercased(), duration), seconds: 3)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportCancelled() {
        exportProgress = nil
        showLCD("EXPORT", "CANCELLED")
    }

    private func exportFailed(_ error: Error) {
        exportProgress = nil
        report("Export fehlgeschlagen", error.localizedDescription)
    }
}
