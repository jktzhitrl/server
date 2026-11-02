import SwiftUI
import NexoraCore

@main
struct NexoraSamplerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = SamplerController()

    var body: some Scene {
        Window("NEXORA Sampler", id: "main") {
            MainView()
                .environment(controller)
                .onAppear {
                    appDelegate.controller = controller
                    ScreenshotDirector.startIfRequested(controller)
                }
                .frame(minWidth: 960, minHeight: 520)
        }
        .defaultSize(width: 1400, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(controller: controller) }

        Settings {
            SettingsView()
                .environment(controller)
        }
    }
}

/// Menüs und Tastenkürzel.
struct AppCommands: Commands {
    let controller: SamplerController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neues Projekt …") { controller.newProject() }
                .keyboardShortcut("n")
            Button("Neues leeres Projekt") { controller.newProject(.empty) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Projekt öffnen …") { controller.openProjectWithPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Sichern") { controller.saveProject() }
                .keyboardShortcut("s")
            Button("Sichern unter …") { controller.saveProjectAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Samples importieren …") { controller.importSamplesWithPanel() }
                .keyboardShortcut("i")
            Button("Sample auf ausgewähltes Pad laden …") { controller.chooseSampleForSelectedPad() }
                .keyboardShortcut("l")
            Divider()
            Button("Audio exportieren …") { controller.showExportSheet = true }
                .keyboardShortcut("e")
        }
        CommandMenu("Transport") {
            Button("Play / Stop (Leertaste)") { controller.togglePlay() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Pause") { controller.pause() }
                .keyboardShortcut(".", modifiers: .command)
            Button("Aufnahme") { controller.toggleRecord() }
                .keyboardShortcut("r")
            Button("Metronom") { controller.toggleMetronome() }
                .keyboardShortcut("k")
            Button("Tap Tempo") { controller.tapTempo() }
                .keyboardShortcut("t")
            Divider()
            ForEach(0..<SequencerState.patternSlots, id: \.self) { slot in
                Button("Pattern \(SequencerState.slotName(slot))") { controller.selectPattern(slot) }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot + 1)")), modifiers: .command)
            }
        }
        CommandMenu("Pads") {
            Button("Trigger-Modus (Pads spielen)") { controller.setPadMode(.play) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Sequencer-Modus (Pads = Schritte)") { controller.setPadMode(.step) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Keyboard-Modus (chromatisch)") { controller.setPadMode(.keyboard) }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Button("Keyboard: Oktave höher") { controller.keyboardOctave = min(controller.keyboardOctave + 1, 3) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Keyboard: Oktave tiefer") { controller.keyboardOctave = max(controller.keyboardOctave - 1, -3) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Pad-Editor") { controller.drawer = .editor }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Sequencer") { controller.drawer = .sequencer }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Sample-Browser") { controller.drawer = .browser }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Master-Effekte") { controller.drawer = .effects }
                .keyboardShortcut("4", modifiers: [.command, .option])
            Button("Kits & Presets") { controller.drawer = .kits }
                .keyboardShortcut("5", modifiers: [.command, .option])
            Button("MIDI") { controller.drawer = .midi }
                .keyboardShortcut("6", modifiers: [.command, .option])
            Button("Bereich schließen") { controller.drawer = nil }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button("MIDI-Learn") { controller.toggleMIDILearn() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Alle Noten aus") { controller.host.send(.allNotesOff) }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
