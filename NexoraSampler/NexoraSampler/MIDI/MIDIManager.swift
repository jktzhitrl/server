import Foundation
import CoreMIDI
import NexoraCore

/// Thread-sicherer Schnappschuss der MIDI-Zuordnung für den MIDI-Empfangsthread.
final class MIDIRouting: @unchecked Sendable {
    private let lock = NSLock()
    private var settings = MIDISettings()
    private var enabled = true

    func update(_ newSettings: MIDISettings, enabled: Bool = true) {
        lock.lock()
        settings = newSettings
        self.enabled = enabled
        lock.unlock()
    }

    func snapshot() -> (MIDISettings, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (settings, enabled)
    }
}

/// Core-MIDI-Anbindung: empfängt von allen MIDI-Quellen (Keyboards, Pad-Controller)
/// und reagiert auf das An- und Abstecken von Geräten.
final class MIDIManager {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []

    /// Aufruf im MIDI-Thread (geringste Latenz für Noten).
    var onMessage: ((MIDIMessage) -> Void)?
    /// Aufruf auf dem Haupt-Thread, wenn sich die Geräteliste ändert.
    var onSourcesChanged: (([String]) -> Void)?

    private(set) var sourceNames: [String] = []
    private(set) var isActive = false

    func start() -> String? {
        var status = MIDIClientCreateWithBlock("NEXORA Sampler" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.connectAllSources() }
            }
        }
        guard status == noErr else { return "MIDI-Client konnte nicht erstellt werden (Fehler \(status))." }
        status = MIDIInputPortCreateWithProtocol(client, "NEXORA Input" as CFString, ._1_0, &inputPort) { [weak self] eventList, _ in
            self?.receive(eventList)
        }
        guard status == noErr else { return "MIDI-Eingang konnte nicht erstellt werden (Fehler \(status))." }
        isActive = true
        connectAllSources()
        return nil
    }

    func connectAllSources() {
        guard isActive else { return }
        for source in connectedSources { _ = MIDIPortDisconnectSource(inputPort, source) }
        connectedSources.removeAll()
        var names: [String] = []
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connectedSources.append(source)
                names.append(Self.displayName(of: source))
            }
        }
        sourceNames = names
        onSourcesChanged?(names)
    }

    private static func displayName(of object: MIDIObjectRef) -> String {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &value)
        guard status == noErr, let value else { return "MIDI-Gerät" }
        return value.takeRetainedValue() as String
    }

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        guard let onMessage else { return }
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            guard count > 0 else { continue }
            let words: [UInt32] = withUnsafeBytes(of: packet.pointee.words) { raw in
                let all = raw.bindMemory(to: UInt32.self)
                return Array(all.prefix(min(count, all.count)))
            }
            for message in MIDIParser.parse(umpWords: words) { onMessage(message) }
        }
    }
}
