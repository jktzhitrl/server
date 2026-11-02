import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio
import NexoraCore

/// Verbindet die `SamplerEngine` über einen `AVAudioSourceNode` mit `AVAudioEngine`.
///
/// Der Render-Callback ruft direkt `SamplerEngine.render` auf – ohne zusätzliche
/// Puffer oder Threads. Die Latenz entspricht damit der Puffergröße des Ausgabegeräts.
final class AudioEngineHost: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var configurationObserver: NSObjectProtocol?
    private let lock = NSLock()
    private var _sampler: SamplerEngine

    /// Wird nach einem Neuaufbau (z. B. Gerätewechsel mit neuer Abtastrate) auf dem
    /// Haupt-Thread aufgerufen, damit der gesamte Zustand erneut übertragen werden kann.
    var onEngineRebuilt: ((SamplerEngine) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var sampleRate: Double
    private(set) var isRunning = false
    private(set) var preferredBufferSize: UInt32 = 256

    init() {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = rate > 0 ? rate : 48_000
        _sampler = SamplerEngine(sampleRate: sampleRate)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
    }

    /// Aktuelle Engine-Instanz (thread-sicher, z. B. für den MIDI-Thread).
    var sampler: SamplerEngine {
        lock.lock()
        defer { lock.unlock() }
        return _sampler
    }

    /// Sendet einen Befehl an die Engine (beliebiger Thread).
    func send(_ command: EngineCommand) {
        sampler.send(command)
    }

    func start() {
        do {
            attachSourceNode()
            engine.prepare()
            try engine.start()
            isRunning = true
            applyBufferSize(preferredBufferSize)
        } catch {
            isRunning = false
            onError?("Audio-Ausgabe konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    private func attachSourceNode() {
        if let node = sourceNode {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
            sourceNode = nil
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let renderer = sampler
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let right = buffers.count > 1 ? (buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? left) : left
            renderer.render(frameCount: Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        sourceNode = node
    }

    /// Baut die Engine nach einer Konfigurationsänderung (Gerät, Abtastrate) neu auf.
    private func rebuild() {
        engine.stop()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let newRate = rate > 0 ? rate : sampleRate
        if newRate != sampleRate {
            let newSampler = SamplerEngine(sampleRate: newRate)
            lock.lock()
            _sampler = newSampler
            sampleRate = newRate
            lock.unlock()
            onEngineRebuilt?(newSampler)
        }
        start()
    }

    // MARK: Resampling

    /// Nimmt die Summe am Ausgang ab (Resampling). Der Block erhält Stereo-Puffer im Tap-Thread.
    func installOutputTap(_ block: @escaping @Sendable (UnsafePointer<Float>, UnsafePointer<Float>?, Int) -> Void) {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 2048, format: mixer.outputFormat(forBus: 0)) { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let right = buffer.format.channelCount > 1 ? UnsafePointer(data[1]) : nil
            block(UnsafePointer(data[0]), right, n)
        }
    }

    func removeOutputTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    // MARK: Geräte

    var currentOutputDevice: AudioDeviceID? {
        guard let unit = engine.outputNode.audioUnit else { return nil }
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size)
        return status == noErr && device != 0 ? device : nil
    }

    /// Wählt ein Ausgabegerät (`nil` = Systemstandard).
    func selectOutputDevice(_ id: AudioDeviceID?) {
        guard let unit = engine.outputNode.audioUnit else { return }
        guard var device = id ?? AudioDeviceManager.defaultOutputDevice() else { return }
        engine.stop()
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            onError?("Das Audiogerät konnte nicht ausgewählt werden (Fehler \(status)).")
        }
        rebuild()
    }

    func applyBufferSize(_ frames: UInt32) {
        preferredBufferSize = frames
        guard let device = currentOutputDevice else { return }
        AudioDeviceManager.setBufferFrameSize(frames, for: device)
    }

    var currentBufferSize: UInt32 {
        currentOutputDevice.flatMap { AudioDeviceManager.bufferFrameSize($0) } ?? preferredBufferSize
    }

    /// Geschätzte Ausgabelatenz in Millisekunden (Puffer + Gerätelatenz).
    var estimatedLatencyMs: Double {
        guard let device = currentOutputDevice else { return Double(preferredBufferSize) / sampleRate * 1000 }
        let frames = Double(currentBufferSize) + Double(AudioDeviceManager.outputLatencyFrames(device))
        return frames / sampleRate * 1000
    }
}
