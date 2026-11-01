import Foundation

/// Plattformunabhängiger Leser für WAV- und AIFF-Dateien (PCM 8/16/24/32 Bit, Float 32/64).
/// Unter macOS werden zusätzlich MP3/M4A über AVFoundation gelesen (`AudioFileLoader`);
/// dieser Leser dient als Fallback und für Tests.
public enum AudioFileReader {
    public struct Decoded {
        public var sampleRate: Double
        public var channels: [[Float]]
    }

    public enum ReaderError: Error, LocalizedError {
        case unsupported(String)
        case corrupt

        public var errorDescription: String? {
            switch self {
            case .unsupported(let s): return "Nicht unterstütztes Audioformat: \(s)"
            case .corrupt: return "Die Audiodatei ist beschädigt."
            }
        }
    }

    public static func read(url: URL) throws -> Decoded {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> Decoded {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw ReaderError.corrupt }
        let tag = String(bytes: bytes[0..<4], encoding: .ascii)
        if tag == "RIFF" { return try decodeWAV(bytes) }
        if tag == "FORM" { return try decodeAIFF(bytes) }
        throw ReaderError.unsupported(tag ?? "?")
    }

    private static func u16le(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    private static func u32le(_ b: [UInt8], _ o: Int) -> Int { u16le(b, o) | u16le(b, o + 2) << 16 }
    private static func u16be(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }
    private static func u32be(_ b: [UInt8], _ o: Int) -> Int { u16be(b, o) << 16 | u16be(b, o + 2) }

    private static func decodeWAV(_ b: [UInt8]) throws -> Decoded {
        var offset = 12
        var channels = 0, sampleRate = 0, bits = 0, formatTag = 0
        var dataRange: Range<Int>?
        while offset + 8 <= b.count {
            let id = String(bytes: b[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = u32le(b, offset + 4)
            let body = offset + 8
            guard body + size <= b.count || id == "data" else { break }
            if id == "fmt " {
                formatTag = u16le(b, body)
                channels = u16le(b, body + 2)
                sampleRate = u32le(b, body + 4)
                bits = u16le(b, body + 14)
                if formatTag == 0xFFFE && size >= 26 { formatTag = u16le(b, body + 24) }
            } else if id == "data" {
                dataRange = body..<min(body + size, b.count)
            }
            offset = body + size + (size % 2)
        }
        guard let range = dataRange, channels > 0, bits > 0 else { throw ReaderError.corrupt }
        let isFloat = formatTag == 3
        guard formatTag == 1 || isFloat else { throw ReaderError.unsupported("WAV Format \(formatTag)") }
        return Decoded(sampleRate: Double(sampleRate),
                       channels: deinterleave(b, range: range, channels: channels, bits: bits, isFloat: isFloat, bigEndian: false))
    }

    private static func decodeAIFF(_ b: [UInt8]) throws -> Decoded {
        let formType = String(bytes: b[8..<12], encoding: .ascii)
        guard formType == "AIFF" || formType == "AIFC" else { throw ReaderError.unsupported(formType ?? "?") }
        var offset = 12
        var channels = 0, bits = 0
        var sampleRate = 0.0
        var dataRange: Range<Int>?
        var isFloat = false
        while offset + 8 <= b.count {
            let id = String(bytes: b[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = u32be(b, offset + 4)
            let body = offset + 8
            if id == "COMM" {
                channels = u16be(b, body)
                bits = u16be(b, body + 6)
                sampleRate = parseExtended(Array(b[body + 8..<body + 18]))
                if formType == "AIFC" && size >= 22 {
                    let comp = String(bytes: b[body + 18..<body + 22], encoding: .ascii) ?? ""
                    if comp == "fl32" || comp == "FL32" { isFloat = true; bits = 32 }
                    else if comp != "NONE" { throw ReaderError.unsupported("AIFC \(comp)") }
                }
            } else if id == "SSND" {
                let dataOffset = u32be(b, body)
                let start = body + 8 + dataOffset
                dataRange = start..<min(body + size, b.count)
            }
            offset = body + size + (size % 2)
        }
        guard let range = dataRange, channels > 0, bits > 0 else { throw ReaderError.corrupt }
        return Decoded(sampleRate: sampleRate,
                       channels: deinterleave(b, range: range, channels: channels, bits: bits, isFloat: isFloat, bigEndian: true))
    }

    static func parseExtended(_ e: [UInt8]) -> Double {
        guard e.count == 10 else { return 44_100 }
        let exponent = (Int(e[0] & 0x7F) << 8 | Int(e[1])) - 16_383
        var mantissa: UInt64 = 0
        for i in 0..<8 { mantissa = mantissa << 8 | UInt64(e[2 + i]) }
        return Double(mantissa) / pow(2, 63) * pow(2, Double(exponent))
    }

    private static func deinterleave(_ b: [UInt8], range: Range<Int>, channels: Int, bits: Int,
                                     isFloat: Bool, bigEndian: Bool) -> [[Float]] {
        let bytesPerSample = bits / 8
        let frameSize = bytesPerSample * channels
        let frames = range.count / max(frameSize, 1)
        var out = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
        for f in 0..<frames {
            for c in 0..<channels {
                let o = range.lowerBound + f * frameSize + c * bytesPerSample
                var raw: UInt64 = 0
                for k in 0..<bytesPerSample {
                    let byte = UInt64(b[o + (bigEndian ? k : bytesPerSample - 1 - k)])
                    raw = raw << 8 | byte
                }
                let value: Float
                if isFloat {
                    value = bits == 64 ? Float(Double(bitPattern: raw)) : Float(bitPattern: UInt32(truncatingIfNeeded: raw))
                } else if bits == 8 && !bigEndian {
                    value = (Float(raw) - 128) / 128 // WAV 8 Bit ist vorzeichenlos
                } else {
                    let shift = 64 - bits
                    let signed = Int64(bitPattern: raw << UInt64(shift)) >> Int64(shift)
                    value = Float(signed) / Float(1 << (bits - 1))
                }
                out[c][f] = value
            }
        }
        return out
    }
}
