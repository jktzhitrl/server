import Foundation

/// Schreibt Stereo-Audio als WAV (RIFF) oder AIFF. Eigene Implementierung ohne
/// Framework-Abhängigkeit, damit der Export auf allen Plattformen identisch und testbar ist.
public enum AudioFileWriter {
    public enum WriterError: Error, LocalizedError {
        case unsupportedCombination(String)
        case empty

        public var errorDescription: String? {
            switch self {
            case .unsupportedCombination(let s): return s
            case .empty: return "Es sind keine Audiodaten vorhanden."
            }
        }
    }

    /// Erzeugt die Dateidaten.
    /// - Note: AIFF unterstützt hier 16/24 Bit PCM; 32-Bit-Float wird als WAV geschrieben.
    public static func encode(left: [Float], right: [Float], sampleRate: Double,
                              format: ExportFileFormat, bitDepth: ExportBitDepth, dither: Bool = true) throws -> Data {
        let frames = min(left.count, right.count)
        guard frames > 0 else { throw WriterError.empty }
        if format == .aiff && bitDepth == .float32 {
            throw WriterError.unsupportedCombination("AIFF unterstützt in NEXORA nur 16 oder 24 Bit. Bitte WAV für 32-Bit-Float wählen.")
        }
        let bigEndian = format == .aiff
        let pcm = encodeSamples(left: left, right: right, frames: frames, bitDepth: bitDepth,
                                bigEndian: bigEndian, dither: dither)
        switch format {
        case .wav: return wavFile(pcm: pcm, frames: frames, sampleRate: sampleRate, bitDepth: bitDepth)
        case .aiff: return aiffFile(pcm: pcm, frames: frames, sampleRate: sampleRate, bitDepth: bitDepth)
        }
    }

    public static func write(left: [Float], right: [Float], sampleRate: Double, format: ExportFileFormat,
                             bitDepth: ExportBitDepth, to url: URL, dither: Bool = true) throws {
        let data = try encode(left: left, right: right, sampleRate: sampleRate, format: format, bitDepth: bitDepth, dither: dither)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Samples

    private static func encodeSamples(left: [Float], right: [Float], frames: Int, bitDepth: ExportBitDepth,
                                      bigEndian: Bool, dither: Bool) -> Data {
        var data = Data()
        var rng = FastRandom(seed: 0xDEC0DE)
        switch bitDepth {
        case .pcm16:
            data.reserveCapacity(frames * 4)
            let scale: Float = 32_767
            for i in 0..<frames {
                for ch in 0..<2 {
                    var x = (ch == 0 ? left[i] : right[i]) * scale
                    if dither { x += (rng.nextBipolar() + rng.nextBipolar()) * 0.5 } // TPDF, ±1 LSB
                    let v = Int16(DSP.clamp(x.rounded(), -32_768, 32_767))
                    appendInt(&data, Int(v), bytes: 2, bigEndian: bigEndian)
                }
            }
        case .pcm24:
            data.reserveCapacity(frames * 6)
            let scale: Float = 8_388_607
            for i in 0..<frames {
                for ch in 0..<2 {
                    let x = DSP.clamp((ch == 0 ? left[i] : right[i]), -1, 1) * scale
                    let v = Int32(DSP.clamp(x.rounded(), -8_388_608, 8_388_607))
                    appendInt(&data, Int(v), bytes: 3, bigEndian: bigEndian)
                }
            }
        case .float32:
            data.reserveCapacity(frames * 8)
            for i in 0..<frames {
                for ch in 0..<2 {
                    let bits = (ch == 0 ? left[i] : right[i]).bitPattern
                    appendInt(&data, Int(bits), bytes: 4, bigEndian: bigEndian)
                }
            }
        }
        return data
    }

    @inline(__always)
    private static func appendInt(_ data: inout Data, _ value: Int, bytes: Int, bigEndian: Bool) {
        let v = UInt64(bitPattern: Int64(value))
        if bigEndian {
            for b in stride(from: bytes - 1, through: 0, by: -1) { data.append(UInt8((v >> (8 * UInt64(b))) & 0xFF)) }
        } else {
            for b in 0..<bytes { data.append(UInt8((v >> (8 * UInt64(b))) & 0xFF)) }
        }
    }

    private static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    private static func bits(_ depth: ExportBitDepth) -> Int {
        switch depth {
        case .pcm16: return 16
        case .pcm24: return 24
        case .float32: return 32
        }
    }

    // MARK: WAV

    private static func wavFile(pcm: Data, frames: Int, sampleRate: Double, bitDepth: ExportBitDepth) -> Data {
        let channels = 2
        let bps = bits(bitDepth)
        let blockAlign = channels * bps / 8
        let byteRate = Int(sampleRate) * blockAlign
        let formatTag: UInt16 = bitDepth == .float32 ? 3 : 1
        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        let padByte = pcm.count % 2
        d.append(contentsOf: le32(UInt32(4 + 8 + 16 + 8 + pcm.count + padByte)))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.append(contentsOf: le32(16))
        d.append(contentsOf: le16(formatTag))
        d.append(contentsOf: le16(UInt16(channels)))
        d.append(contentsOf: le32(UInt32(sampleRate)))
        d.append(contentsOf: le32(UInt32(byteRate)))
        d.append(contentsOf: le16(UInt16(blockAlign)))
        d.append(contentsOf: le16(UInt16(bps)))
        d.append(contentsOf: Array("data".utf8))
        d.append(contentsOf: le32(UInt32(pcm.count)))
        d.append(pcm)
        if padByte == 1 { d.append(0) }
        return d
    }

    // MARK: AIFF

    /// 80-Bit-IEEE-754-Extended (für das AIFF-COMM-Feld der Abtastrate).
    static func extended80(_ value: Double) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 10)
        guard value > 0 else { return bytes }
        var exponent = Int(floor(log2(value)))
        var mantissa = value / pow(2, Double(exponent))
        // Normalisieren auf 1 ≤ m < 2
        while mantissa >= 2 { mantissa /= 2; exponent += 1 }
        while mantissa < 1 { mantissa *= 2; exponent -= 1 }
        let biased = UInt16(exponent + 16_383)
        let m = UInt64(mantissa * pow(2, 63))
        bytes[0] = UInt8(biased >> 8)
        bytes[1] = UInt8(biased & 0xFF)
        for i in 0..<8 { bytes[2 + i] = UInt8((m >> (8 * UInt64(7 - i))) & 0xFF) }
        return bytes
    }

    private static func aiffFile(pcm: Data, frames: Int, sampleRate: Double, bitDepth: ExportBitDepth) -> Data {
        let channels = 2
        let bps = bits(bitDepth)
        let padByte = pcm.count % 2
        let commSize = 18
        let ssndSize = 8 + pcm.count
        var d = Data()
        d.append(contentsOf: Array("FORM".utf8))
        d.append(contentsOf: be32(UInt32(4 + 8 + commSize + 8 + ssndSize + padByte)))
        d.append(contentsOf: Array("AIFF".utf8))
        d.append(contentsOf: Array("COMM".utf8))
        d.append(contentsOf: be32(UInt32(commSize)))
        d.append(contentsOf: be16(UInt16(channels)))
        d.append(contentsOf: be32(UInt32(frames)))
        d.append(contentsOf: be16(UInt16(bps)))
        d.append(contentsOf: extended80(sampleRate))
        d.append(contentsOf: Array("SSND".utf8))
        d.append(contentsOf: be32(UInt32(ssndSize)))
        d.append(contentsOf: be32(0)) // offset
        d.append(contentsOf: be32(0)) // blockSize
        d.append(pcm)
        if padByte == 1 { d.append(0) }
        return d
    }
}
