import Foundation

/// Bausteine der Klangsynthese für die Werks-Bibliothek. Alle Klänge werden deterministisch
/// erzeugt (feste Zufalls-Seeds), damit jede Installation identische Samples erhält.
struct SoundLab {
    let sampleRate: Double

    enum Wave { case sine, saw, square, triangle }

    func frames(_ seconds: Double) -> Int { max(1, Int(seconds * sampleRate)) }

    static func midiToHz(_ note: Double) -> Double { 440 * pow(2, (note - 69) / 12) }

    @inline(__always)
    static func wave(_ w: Wave, _ phase: Double) -> Double {
        let p = phase - floor(phase)
        switch w {
        case .sine: return sin(2 * .pi * p)
        case .saw: return 2 * p - 1
        case .square: return p < 0.5 ? 1 : -1
        case .triangle: return p < 0.5 ? 4 * p - 1 : 3 - 4 * p
        }
    }

    // MARK: Nachbearbeitung

    static func normalize(_ x: [Float], peak: Float = 0.89) -> [Float] {
        let m = x.map(abs).max() ?? 0
        guard m > 0 else { return x }
        let g = peak / m
        return x.map { $0 * g }
    }

    static func normalize(_ channels: [[Float]], peak: Float = 0.89) -> [[Float]] {
        let m = channels.flatMap { $0 }.map(abs).max() ?? 0
        guard m > 0 else { return channels }
        let g = peak / m
        return channels.map { $0.map { $0 * g } }
    }

    static func fade(_ x: inout [Float], inSamples: Int = 0, outSamples: Int = 64) {
        let n = x.count
        for i in 0..<min(inSamples, n) { x[i] *= Float(i) / Float(max(inSamples, 1)) }
        for i in 0..<min(outSamples, n) { x[n - 1 - i] *= Float(i) / Float(max(outSamples, 1)) }
    }

    /// Stereo durch leicht verzögerten, gemischten rechten Kanal.
    func widen(_ mono: [Float], amount: Float, delayMs: Double = 0.35) -> [[Float]] {
        guard amount > 0 else { return [mono] }
        let d = max(1, Int(delayMs / 1000 * sampleRate))
        var r = mono
        for i in stride(from: mono.count - 1, through: d, by: -1) { r[i] = mono[i] * (1 - amount) + mono[i - d] * amount }
        return [mono, r]
    }

    func drive(_ x: [Float], _ amount: Float) -> [Float] {
        guard amount > 0 else { return x }
        let g = 1 + amount * 10
        return x.map { DSP.fastTanh($0 * g) }
    }

    func reversed(_ c: [[Float]]) -> [[Float]] { c.map { Array($0.reversed()) } }

    /// Filter mit zeitabhängigem Cutoff (Hz), alle 32 Samples aktualisiert.
    func filter(_ x: [Float], mode: FilterMode, resonance: Float = 0.2, cutoff: (Double) -> Double) -> [Float] {
        var f = StateVariableFilter()
        f.mode = mode
        var out = x
        for i in 0..<x.count {
            if i % 32 == 0 {
                f.setParameters(cutoff: Float(cutoff(Double(i) / sampleRate)), resonance: resonance, sampleRate: Float(sampleRate))
            }
            out[i] = f.processMono(x[i])
        }
        return out
    }

    func filter(_ x: [Float], mode: FilterMode, cutoff: Double, resonance: Float = 0.2) -> [Float] {
        filter(x, mode: mode, resonance: resonance) { _ in cutoff }
    }

    // MARK: Quellen

    func noise(_ n: Int, seed: UInt32) -> [Float] {
        var r = FastRandom(seed: seed)
        return (0..<n).map { _ in r.nextBipolar() }
    }

    /// Sechs inharmonische Rechtecke – metallisches Rauschen für Becken und Hi-Hats.
    func metallic(_ n: Int, scale: Double = 1) -> [Float] {
        let freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].map { $0 * 1.62 * scale }
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for f in freqs { s += sin(2 * .pi * f * t) >= 0 ? 1 : -1 }
            return Float(s / 6)
        }
    }

    /// Oszillator mit Tonhöhenverlauf (Hz über Zeit) und Amplitudenverlauf.
    func osc(_ wave: Wave, seconds: Double, freq: (Double) -> Double, amp: (Double) -> Double) -> [Float] {
        let n = frames(seconds)
        var phase = 0.0
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] = Float(Self.wave(wave, phase) * amp(t))
            phase += freq(t) / sampleRate
        }
        return out
    }

    /// Mehrere leicht verstimmte Oszillatoren je Note (Supersaw-Prinzip).
    func stack(_ wave: Wave, notes: [Double], seconds: Double, voices: Int = 2, detuneCents: Double = 8,
               amp: (Double) -> Double, stereo: Bool = true) -> [[Float]] {
        let n = frames(seconds)
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        var phases = [Double](repeating: 0, count: notes.count * voices)
        var rng = FastRandom(seed: 0xA11CE)
        for i in phases.indices { phases[i] = Double(rng.nextBipolar() + 1) / 2 }
        let total = Double(notes.count * voices)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let a = amp(t)
            var l = 0.0, r = 0.0
            for (k, note) in notes.enumerated() {
                let base = Self.midiToHz(note)
                for v in 0..<voices {
                    let spread = voices == 1 ? 0 : (Double(v) / Double(voices - 1) * 2 - 1) * detuneCents
                    let idx = k * voices + v
                    phases[idx] += base * pow(2, spread / 1200) / sampleRate
                    let s = Self.wave(wave, phases[idx])
                    if v % 2 == 0 { l += s; r += s * 0.6 } else { r += s; l += s * 0.6 }
                }
            }
            left[i] = Float(l / total * a)
            right[i] = Float(r / total * a)
        }
        return stereo ? [left, right] : [zip(left, right).map { ($0 + $1) / 2 }]
    }

    /// Zwei-Operator-FM.
    func fm(carrier: Double, ratio: Double, index: (Double) -> Double, seconds: Double, amp: (Double) -> Double) -> [Float] {
        let n = frames(seconds)
        var pc = 0.0, pm = 0.0
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let mod = sin(2 * .pi * pm) * index(t)
            out[i] = Float(sin(2 * .pi * pc + mod) * amp(t))
            pc += carrier / sampleRate
            pm += carrier * ratio / sampleRate
        }
        return out
    }

    // MARK: Hüllkurven

    static func expDecay(_ t: Double, _ tau: Double) -> Double { exp(-t / max(tau, 0.0001)) }

    static func ar(_ t: Double, attack: Double, release: Double, length: Double) -> Double {
        if t < attack { return t / attack }
        let rStart = length - release
        if t > rStart { return max(0, (length - t) / release) }
        return 1
    }
}

/// Formanten für Vokal-Chops (F1, F2, F3 in Hz).
enum Vowel: String, CaseIterable {
    case a, e, i, o, u

    var formants: [Double] {
        switch self {
        case .a: return [800, 1150, 2900]
        case .e: return [400, 1600, 2700]
        case .i: return [270, 2140, 2950]
        case .o: return [450, 800, 2830]
        case .u: return [325, 700, 2530]
        }
    }
}
