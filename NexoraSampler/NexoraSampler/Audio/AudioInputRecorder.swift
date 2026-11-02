import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

/// Aufnahme vom Audio-Eingang (Mikrofon, Line-In, Interface) über eine eigene `AVAudioEngine`,
/// damit die Wiedergabe-Engine unverändert weiterläuft.
final class AudioInputRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    /// Abtastrate des Eingangs (nach dem Start gültig)
    private(set) var sampleRate: Double = 48_000

    /// Wählt das Eingangsgerät (`nil` = Standard) und liefert die Abtastrate des Eingangs.
    func prepare(device: AudioDeviceID?) throws -> Double {
        stop()
        let input = engine.inputNode
        if var id = device, let unit = input.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                throw NSError(domain: "NEXORA", code: Int(status),
                              userInfo: [NSLocalizedDescriptionKey: "Das Eingangsgerät konnte nicht gewählt werden (Fehler \(status))."])
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "NEXORA", code: -1, userInfo: [NSLocalizedDescriptionKey:
                "Kein Audio-Eingang verfügbar. Bitte Mikrofon oder Interface anschließen und den Zugriff unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon erlauben."])
        }
        sampleRate = format.sampleRate
        return format.sampleRate
    }

    /// Startet die Aufnahme (nach `prepare`). Der Block erhält die Kanäle im Tap-Thread.
    /// - Parameter monitor: Eingang zusätzlich über den Standard-Ausgang hörbar machen
    func start(monitor: Bool, block: @escaping @Sendable (UnsafePointer<Float>, UnsafePointer<Float>?, Int) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let right = buffer.format.channelCount > 1 ? UnsafePointer(data[1]) : nil
            block(UnsafePointer(data[0]), right, Int(buffer.frameLength))
        }
        if monitor {
            engine.connect(input, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 1
        } else {
            engine.mainMixerNode.outputVolume = 0
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.disconnectNodeOutput(engine.inputNode)
        engine.stop()
        running = false
    }

    /// Fragt (falls nötig) die Mikrofon-Freigabe an.
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
