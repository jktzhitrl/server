import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Vektor-Operationen. Unter macOS über das Accelerate-Framework (vDSP),
/// sonst über skalare Schleifen (identische Semantik, z. B. für Linux-Tests).
public enum VectorOps {
    @inline(__always)
    public static func clear(_ buffer: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        #if canImport(Accelerate)
        vDSP_vclr(buffer, 1, vDSP_Length(count))
        #else
        buffer.update(repeating: 0, count: count)
        #endif
    }

    /// destination += source * scale
    @inline(__always)
    public static func addScaled(_ source: UnsafePointer<Float>, scale: Float,
                                 into destination: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        #if canImport(Accelerate)
        var s = scale
        vDSP_vsma(source, 1, &s, destination, 1, destination, 1, vDSP_Length(count))
        #else
        for i in 0..<count { destination[i] += source[i] * scale }
        #endif
    }

    /// buffer *= scale
    @inline(__always)
    public static func scale(_ buffer: UnsafeMutablePointer<Float>, by scale: Float, count: Int) {
        guard count > 0 else { return }
        #if canImport(Accelerate)
        var s = scale
        vDSP_vsmul(buffer, 1, &s, buffer, 1, vDSP_Length(count))
        #else
        for i in 0..<count { buffer[i] *= scale }
        #endif
    }

    /// Maximaler Betrag (Peak).
    @inline(__always)
    public static func peak(_ buffer: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        #if canImport(Accelerate)
        var result: Float = 0
        vDSP_maxmgv(buffer, 1, &result, vDSP_Length(count))
        return result
        #else
        var m: Float = 0
        for i in 0..<count { m = max(m, abs(buffer[i])) }
        return m
        #endif
    }

    /// Effektivwert (RMS).
    public static func rms(_ buffer: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        #if canImport(Accelerate)
        var result: Float = 0
        vDSP_rmsqv(buffer, 1, &result, vDSP_Length(count))
        return result
        #else
        var sum: Float = 0
        for i in 0..<count { sum += buffer[i] * buffer[i] }
        return sqrtf(sum / Float(count))
        #endif
    }

    /// Begrenzt alle Werte auf -limit ... limit.
    @inline(__always)
    public static func clip(_ buffer: UnsafeMutablePointer<Float>, limit: Float, count: Int) {
        guard count > 0 else { return }
        #if canImport(Accelerate)
        var lo = -limit
        var hi = limit
        vDSP_vclip(buffer, 1, &lo, &hi, buffer, 1, vDSP_Length(count))
        #else
        for i in 0..<count { buffer[i] = min(max(buffer[i], -limit), limit) }
        #endif
    }

    /// Wellenform-Übersicht: Spitzenwert je Abschnitt (für die Darstellung im Display).
    public static func overview(_ samples: UnsafePointer<Float>, count: Int, bins: Int) -> [Float] {
        guard count > 0, bins > 0 else { return [] }
        var result = [Float](repeating: 0, count: bins)
        let perBin = max(1, count / bins)
        for b in 0..<bins {
            let start = b * count / bins
            let length = min(perBin, count - start)
            if length > 0 { result[b] = peak(samples + start, count: length) }
        }
        return result
    }
}
