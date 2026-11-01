import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Lädt Audiodateien in einen `SampleBuffer`.
/// Unter macOS über `AVAudioFile` (WAV, AIFF, MP3, M4A/AAC/ALAC, CAF, FLAC),
/// auf anderen Plattformen über den eingebauten WAV/AIFF-Leser.
public enum AudioFileLoader {
    public static let supportedExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "aifc", "mp3", "m4a", "aac", "caf", "flac"]
    /// Maximale Sample-Länge (Schutz vor versehentlich importierten Langdateien)
    public static let maximumDuration: Double = 10 * 60

    public enum LoaderError: Error, LocalizedError {
        case unsupportedFormat(String)
        case empty
        case tooLong(Double)
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext): return "Das Format „\(ext)“ wird nicht unterstützt."
            case .empty: return "Die Datei enthält keine Audiodaten."
            case .tooLong(let d): return String(format: "Das Sample ist zu lang (%.0f s, maximal 600 s).", d)
            case .decodingFailed(let s): return "Die Datei konnte nicht gelesen werden: \(s)"
            }
        }
    }

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func load(url: URL, name: String? = nil) throws -> SampleBuffer {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw LoaderError.unsupportedFormat(ext) }
        let displayName = name ?? url.deletingPathExtension().lastPathComponent
        #if canImport(AVFoundation)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw LoaderError.decodingFailed(error.localizedDescription)
        }
        let format = file.processingFormat
        let length = file.length
        guard length > 0 else { throw LoaderError.empty }
        let duration = Double(length) / format.sampleRate
        guard duration <= maximumDuration else { throw LoaderError.tooLong(duration) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)) else {
            throw LoaderError.decodingFailed("Puffer konnte nicht angelegt werden")
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw LoaderError.decodingFailed(error.localizedDescription)
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0, let data = buffer.floatChannelData else { throw LoaderError.empty }
        let channelCount = min(Int(format.channelCount), 2)
        var channels: [[Float]] = []
        for c in 0..<channelCount {
            channels.append(Array(UnsafeBufferPointer(start: data[c], count: frames)))
        }
        return SampleBuffer(name: displayName, sampleRate: format.sampleRate, channels: channels, sourceURL: url)
        #else
        guard ["wav", "wave", "aif", "aiff", "aifc"].contains(ext) else { throw LoaderError.unsupportedFormat(ext) }
        let decoded = try AudioFileReader.read(url: url)
        guard let first = decoded.channels.first, !first.isEmpty else { throw LoaderError.empty }
        let duration = Double(first.count) / decoded.sampleRate
        guard duration <= maximumDuration else { throw LoaderError.tooLong(duration) }
        return SampleBuffer(name: displayName, sampleRate: decoded.sampleRate,
                            channels: Array(decoded.channels.prefix(2)), sourceURL: url)
        #endif
    }
}
