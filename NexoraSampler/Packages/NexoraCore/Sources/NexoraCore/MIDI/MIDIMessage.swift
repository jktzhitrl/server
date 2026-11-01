import Foundation

/// Geparste MIDI-1.0-Nachricht. Kanäle 1 ... 16.
public enum MIDIMessage: Equatable, Sendable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    case programChange(channel: Int, program: Int)
    case pitchBend(channel: Int, value: Int)
    case start
    case stop
    case `continue`
    case clock
}

/// Parser für MIDI-Bytes (mit Running Status) und Universal-MIDI-Packets (UMP, MIDI 1.0 Protocol),
/// wie sie Core MIDI über `MIDIEventList` liefert.
public struct MIDIParser {
    private var runningStatus: UInt8 = 0
    private var buffer: [UInt8] = []
    private var expected = 0

    public init() {}

    /// Dekodiert ein UMP-Wort (Message Type 0x1 System, 0x2 MIDI-1.0-Channel-Voice).
    public static func parse(umpWord word: UInt32) -> MIDIMessage? {
        let messageType = word >> 28
        let status = UInt8((word >> 16) & 0xFF)
        let data1 = Int((word >> 8) & 0x7F)
        let data2 = Int(word & 0x7F)
        switch messageType {
        case 0x1:
            return systemRealtime(status)
        case 0x2:
            return channelMessage(status: status, data1: data1, data2: data2)
        default:
            return nil
        }
    }

    /// Anzahl der 32-Bit-Wörter eines UMP anhand des Message Types (UMP-Spezifikation 1.1).
    public static func umpWordCount(firstWord: UInt32) -> Int {
        switch firstWord >> 28 {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    /// Dekodiert eine Folge von UMP-Wörtern (z. B. aus einem `MIDIEventPacket`).
    public static func parse(umpWords words: [UInt32]) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if let m = parse(umpWord: w) { result.append(m) }
            i += umpWordCount(firstWord: w)
        }
        return result
    }

    static func systemRealtime(_ status: UInt8) -> MIDIMessage? {
        switch status {
        case 0xF8: return .clock
        case 0xFA: return .start
        case 0xFB: return .continue
        case 0xFC: return .stop
        default: return nil
        }
    }

    static func channelMessage(status: UInt8, data1: Int, data2: Int) -> MIDIMessage? {
        let channel = Int(status & 0x0F) + 1
        switch status & 0xF0 {
        case 0x90:
            return data2 == 0 ? .noteOff(channel: channel, note: data1, velocity: 0)
                              : .noteOn(channel: channel, note: data1, velocity: data2)
        case 0x80: return .noteOff(channel: channel, note: data1, velocity: data2)
        case 0xB0: return .controlChange(channel: channel, controller: data1, value: data2)
        case 0xC0: return .programChange(channel: channel, program: data1)
        case 0xE0: return .pitchBend(channel: channel, value: data1 | (data2 << 7))
        default: return nil
        }
    }

    private static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
        default: return 0
        }
    }

    /// Verarbeitet einen Byte-Strom (MIDI 1.0) inklusive Running Status.
    public mutating func parse(bytes: [UInt8]) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 {
                if let m = Self.systemRealtime(byte) { result.append(m) }
                continue
            }
            if byte & 0x80 != 0 {
                if byte >= 0xF0 {
                    runningStatus = 0 // SysEx/System Common beendet Running Status
                    expected = 0
                    buffer.removeAll()
                    continue
                }
                runningStatus = byte
                expected = Self.dataLength(for: byte)
                buffer.removeAll()
                continue
            }
            guard runningStatus != 0 else { continue }
            buffer.append(byte)
            if buffer.count == expected {
                let d1 = Int(buffer[0])
                let d2 = expected > 1 ? Int(buffer[1]) : 0
                if let m = Self.channelMessage(status: runningStatus, data1: d1, data2: d2) { result.append(m) }
                buffer.removeAll()
            }
        }
        return result
    }
}
