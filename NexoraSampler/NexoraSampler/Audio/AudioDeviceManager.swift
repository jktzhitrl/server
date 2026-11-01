import Foundation
import CoreAudio
import AudioToolbox

/// Ein Audio-Ausgabegerät (Core Audio).
struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let nominalSampleRate: Double
}

/// Abfrage und Konfiguration von Core-Audio-Ausgabegeräten.
enum AudioDeviceManager {
    static let bufferSizeOptions: [UInt32] = [32, 64, 128, 256, 512, 1024]

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func outputDevices() -> [AudioOutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id) else { return nil }
            return AudioOutputDevice(id: id,
                                     uid: stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "\(id)",
                                     name: stringProperty(id, kAudioObjectPropertyName) ?? "Audio Device \(id)",
                                     nominalSampleRate: nominalSampleRate(id) ?? 0)
        }
    }

    static func defaultOutputDevice() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func nominalSampleRate(_ id: AudioDeviceID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate) == noErr ? rate : nil
    }

    static func bufferFrameSize(_ id: AudioDeviceID) -> UInt32? {
        var addr = address(kAudioDevicePropertyBufferFrameSize)
        var frames = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &frames) == noErr ? frames : nil
    }

    /// Setzt die Puffergröße des Geräts (bestimmt die Ausgabelatenz).
    @discardableResult
    static func setBufferFrameSize(_ frames: UInt32, for id: AudioDeviceID) -> Bool {
        var range = AudioValueRange(mMinimum: 0, mMaximum: 0)
        var rangeAddr = address(kAudioDevicePropertyBufferFrameSizeRange)
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        var value = frames
        if AudioObjectGetPropertyData(id, &rangeAddr, 0, nil, &rangeSize, &range) == noErr, range.mMaximum > 0 {
            value = UInt32(min(max(Double(frames), range.mMinimum), range.mMaximum))
        }
        var addr = address(kAudioDevicePropertyBufferFrameSize)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    static func outputLatencyFrames(_ id: AudioDeviceID) -> UInt32 {
        var addr = address(kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput)
        var frames = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &frames)
        return frames
    }
}
