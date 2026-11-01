import Foundation

/// Erzeugt das eingebaute Werks-Kit per Klangsynthese. Dadurch ist die App ohne
/// mitgelieferte Audiodateien und ohne Internet sofort spielbar. Beim Speichern eines
/// Projekts werden diese Klänge als WAV-Dateien in das Projekt geschrieben.
public enum FactoryKit {
    public static let sampleRate: Double = 44_100
    public static let kitName = "NEXORA Factory"

    public struct Sound {
        public let name: String
        public let channels: [[Float]]
        public let settings: PadSettings
    }

    public static let soundNames = [
        "KICK", "SNARE", "CLAP", "RIM",
        "CL HAT", "OP HAT", "SHAKER", "CRASH",
        "TOM LO", "TOM MID", "TOM HI", "COWBELL",
        "808 SUB", "BASS", "STAB", "ZAP"
    ]

    /// Alle 16 Klänge in Pad-Reihenfolge.
    public static func makeSounds() -> [Sound] {
        soundNames.enumerated().map { index, name in
            var settings = PadSettings()
            let channels: [[Float]]
            switch index {
            case 0: channels = kick()
            case 1: channels = snare()
            case 2: channels = clap()
            case 3: channels = rim()
            case 4: channels = hat(decay: 0.045, length: 0.12); settings.chokeGroup = 1
            case 5: channels = hat(decay: 0.38, length: 0.9); settings.chokeGroup = 1
            case 6: channels = shaker()
            case 7: channels = crash()
            case 8: channels = tom(frequency: 95)
            case 9: channels = tom(frequency: 140)
            case 10: channels = tom(frequency: 205)
            case 11: channels = cowbell()
            case 12: channels = sub808(); settings.mono = true
            case 13: channels = bassPluck(); settings.mono = true
            case 14: channels = chordStab()
            default: channels = zap()
            }
            settings.volume = 0.8
            return Sound(name: name, channels: channels, settings: settings)
        }
    }

    public static func makeBuffers() -> [(SampleBuffer, PadSettings)] {
        makeSounds().map { (SampleBuffer(name: $0.name, sampleRate: sampleRate, channels: $0.channels), $0.settings) }
    }

    // MARK: Demo-Patterns

    public static func demoPatterns() -> [SequencerPattern] {
        var a = SequencerPattern(name: "Pattern A")
        for s in [0, 4, 8, 12] { a[0, s] = SequencerStep(active: true, velocity: 1) }
        a[0, 10] = SequencerStep(active: true, velocity: 0.6)
        for s in [4, 12] { a[1, s] = SequencerStep(active: true, velocity: 0.95) }
        a[2, 12] = SequencerStep(active: true, velocity: 0.6)
        for s in stride(from: 0, to: 16, by: 2) { a[4, s] = SequencerStep(active: true, velocity: s % 4 == 0 ? 0.85 : 0.6) }
        a[5, 14] = SequencerStep(active: true, velocity: 0.7)
        for s in [0, 3, 6, 10] { a[12, s] = SequencerStep(active: true, velocity: 0.9) }

        var b = SequencerPattern(name: "Pattern B")
        for s in [0, 7, 10] { b[0, s] = SequencerStep(active: true, velocity: 1) }
        for s in [4, 12] { b[1, s] = SequencerStep(active: true, velocity: 1) }
        b[1, 15] = SequencerStep(active: true, velocity: 0.45)
        for s in 0..<16 { b[6, s] = SequencerStep(active: true, velocity: s % 2 == 0 ? 0.7 : 0.4) }
        b[5, 2] = SequencerStep(active: true, velocity: 0.7)
        for s in [0, 3, 8, 11, 14] { b[13, s] = SequencerStep(active: true, velocity: 0.85) }
        b[14, 0] = SequencerStep(active: true, velocity: 0.8)
        b[15, 15] = SequencerStep(active: true, velocity: 0.7)
        return [a, b]
    }

    // MARK: Synthese-Bausteine

    private static func frames(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

    private static func stereo(_ mono: [Float], width: Float = 0) -> [[Float]] {
        guard width > 0 else { return [mono] }
        var r = mono
        let d = 11
        for i in stride(from: mono.count - 1, through: d, by: -1) { r[i] = mono[i] * (1 - width) + mono[i - d] * width }
        return [mono, r]
    }

    private static func normalize(_ x: [Float], peak: Float = 0.89) -> [Float] {
        let m = x.map(abs).max() ?? 0
        guard m > 0 else { return x }
        let g = peak / m
        return x.map { $0 * g }
    }

    private static func fadeOut(_ x: inout [Float], samples: Int = 64) {
        let n = min(samples, x.count)
        for i in 0..<n { x[x.count - 1 - i] *= Float(i) / Float(n) }
    }

    private static func kick() -> [[Float]] {
        let n = frames(0.6)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let f = 48 + 140 * exp(-t / 0.035)
            phase += 2 * .pi * f / sampleRate
            let amp = exp(-t / 0.28)
            let click = t < 0.004 ? (1 - t / 0.004) * 0.6 : 0
            out[i] = Float(sin(phase) * amp + click * sin(t * 2 * .pi * 3_000))
            out[i] = DSP.fastTanh(out[i] * 1.4)
        }
        fadeOut(&out)
        return [normalize(out)]
    }

    private static func snare() -> [[Float]] {
        let n = frames(0.35)
        var out = [Float](repeating: 0, count: n)
        var rng = FastRandom(seed: 7)
        var hp = StateVariableFilter()
        hp.mode = .highPass
        hp.setParameters(cutoff: 1_800, resonance: 0.1, sampleRate: Float(sampleRate))
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let tone = sin(2 * .pi * 185 * t) * exp(-t / 0.05) * 0.7 + sin(2 * .pi * 330 * t) * exp(-t / 0.03) * 0.3
            let noise = hp.processMono(rng.nextBipolar()) * Float(exp(-t / 0.09))
            out[i] = Float(tone) + noise * 0.9
        }
        fadeOut(&out)
        return stereo(normalize(out), width: 0.2)
    }

    private static func clap() -> [[Float]] {
        let n = frames(0.4)
        var out = [Float](repeating: 0, count: n)
        var rng = FastRandom(seed: 11)
        var bp = StateVariableFilter()
        bp.mode = .bandPass
        bp.setParameters(cutoff: 1_250, resonance: 0.45, sampleRate: Float(sampleRate))
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var env = 0.0
            for burst in [0.0, 0.011, 0.022] where t >= burst { env = max(env, exp(-(t - burst) / 0.007)) }
            if t >= 0.03 { env = max(env, exp(-(t - 0.03) / 0.12) * 0.8) }
            out[i] = bp.processMono(rng.nextBipolar()) * Float(env)
        }
        fadeOut(&out)
        return stereo(normalize(out), width: 0.35)
    }

    private static func rim() -> [[Float]] {
        let n = frames(0.08)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] = Float((sin(2 * .pi * 1_700 * t) * 0.6 + sin(2 * .pi * 455 * t)) * exp(-t / 0.012))
        }
        fadeOut(&out)
        return [normalize(out, peak: 0.8)]
    }

    /// Metallisches Rauschen im Stil klassischer Drum-Machines (sechs inharmonische Rechtecke).
    private static func metallic(_ n: Int) -> [Float] {
        let freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].map { $0 * 1.62 }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            var s = 0.0
            for f in freqs { s += sin(2 * .pi * f * t) >= 0 ? 1 : -1 }
            out[i] = Float(s / 6)
        }
        return out
    }

    private static func hat(decay: Double, length: Double) -> [[Float]] {
        let n = frames(length)
        let metal = metallic(n)
        var rng = FastRandom(seed: 3)
        var hp = StateVariableFilter()
        hp.mode = .highPass
        hp.setParameters(cutoff: 7_500, resonance: 0.2, sampleRate: Float(sampleRate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let src = metal[i] * 0.7 + rng.nextBipolar() * 0.4
            out[i] = hp.processMono(src) * Float(exp(-t / decay))
        }
        fadeOut(&out)
        return stereo(normalize(out, peak: 0.7), width: 0.3)
    }

    private static func shaker() -> [[Float]] {
        let n = frames(0.18)
        var rng = FastRandom(seed: 5)
        var hp = StateVariableFilter()
        hp.mode = .highPass
        hp.setParameters(cutoff: 5_000, resonance: 0.1, sampleRate: Float(sampleRate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = t < 0.015 ? t / 0.015 : exp(-(t - 0.015) / 0.04)
            out[i] = hp.processMono(rng.nextBipolar()) * Float(env)
        }
        fadeOut(&out)
        return stereo(normalize(out, peak: 0.6), width: 0.5)
    }

    private static func crash() -> [[Float]] {
        let n = frames(2.2)
        let metal = metallic(n)
        var rng = FastRandom(seed: 9)
        var hp = StateVariableFilter()
        hp.mode = .highPass
        hp.setParameters(cutoff: 4_000, resonance: 0.1, sampleRate: Float(sampleRate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] = hp.processMono(metal[i] * 0.4 + rng.nextBipolar() * 0.8) * Float(exp(-t / 0.7))
        }
        fadeOut(&out, samples: 2_000)
        return stereo(normalize(out, peak: 0.6), width: 0.6)
    }

    private static func tom(frequency: Double) -> [[Float]] {
        let n = frames(0.5)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let f = frequency * (1 + 0.5 * exp(-t / 0.04))
            phase += 2 * .pi * f / sampleRate
            out[i] = Float(sin(phase) * exp(-t / 0.18))
        }
        fadeOut(&out)
        return [normalize(out, peak: 0.85)]
    }

    private static func cowbell() -> [[Float]] {
        let n = frames(0.45)
        var bp = StateVariableFilter()
        bp.mode = .bandPass
        bp.setParameters(cutoff: 2_600, resonance: 0.3, sampleRate: Float(sampleRate))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let s = (sin(2 * .pi * 540 * t) >= 0 ? 1.0 : -1.0) + (sin(2 * .pi * 800 * t) >= 0 ? 1.0 : -1.0)
            let env = t < 0.02 ? exp(-t / 0.01) * 0.6 + 0.4 : 0.4 * exp(-(t - 0.02) / 0.12)
            out[i] = bp.processMono(Float(s * 0.5)) * Float(env)
        }
        fadeOut(&out)
        return [normalize(out, peak: 0.7)]
    }

    private static func sub808() -> [[Float]] {
        let n = frames(1.5)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let f = 55 * (1 + 0.6 * exp(-t / 0.03))
            phase += 2 * .pi * f / sampleRate
            out[i] = DSP.fastTanh(Float(sin(phase) * exp(-t / 0.7)) * 1.8)
        }
        fadeOut(&out, samples: 500)
        return [normalize(out)]
    }

    private static func bassPluck() -> [[Float]] {
        let n = frames(0.6)
        var lp = StateVariableFilter()
        lp.mode = .lowPass
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            if i % 32 == 0 {
                lp.setParameters(cutoff: Float(180 + 2_800 * exp(-t / 0.08)), resonance: 0.55, sampleRate: Float(sampleRate))
            }
            phase += 55 / sampleRate
            phase -= floor(phase)
            let saw = Float(2 * phase - 1)
            out[i] = lp.processMono(saw) * Float(exp(-t / 0.35))
        }
        fadeOut(&out)
        return [normalize(out, peak: 0.85)]
    }

    private static func chordStab() -> [[Float]] {
        let n = frames(0.9)
        // C-Moll 7: C4, Eb4, G4, Bb4 – je zwei leicht verstimmte Sägezähne
        let notes = [261.63, 311.13, 392.0, 466.16]
        var phases = [Double](repeating: 0, count: notes.count * 2)
        var lpL = StateVariableFilter(), lpR = StateVariableFilter()
        lpL.mode = .lowPass; lpR.mode = .lowPass
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            if i % 32 == 0 {
                let c = Float(600 + 5_000 * exp(-t / 0.12))
                lpL.setParameters(cutoff: c, resonance: 0.25, sampleRate: Float(sampleRate))
                lpR.setParameters(cutoff: c, resonance: 0.25, sampleRate: Float(sampleRate))
            }
            var l = 0.0, r = 0.0
            for (k, f) in notes.enumerated() {
                for d in 0..<2 {
                    let idx = k * 2 + d
                    let freq = f * (d == 0 ? 0.997 : 1.003)
                    phases[idx] += freq / sampleRate
                    phases[idx] -= floor(phases[idx])
                    let saw = 2 * phases[idx] - 1
                    if d == 0 { l += saw } else { r += saw }
                }
            }
            let env = Float(exp(-t / 0.3))
            left[i] = lpL.processMono(Float(l / 4)) * env
            right[i] = lpR.processMono(Float(r / 4)) * env
        }
        fadeOut(&left); fadeOut(&right)
        let m = max(left.map(abs).max() ?? 1, right.map(abs).max() ?? 1)
        return [left.map { $0 * 0.85 / m }, right.map { $0 * 0.85 / m }]
    }

    private static func zap() -> [[Float]] {
        let n = frames(0.3)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let f = 80 + 2_400 * exp(-t / 0.04)
            phase += 2 * .pi * f / sampleRate
            out[i] = Float(sin(phase) * exp(-t / 0.1))
        }
        fadeOut(&out)
        return stereo(normalize(out, peak: 0.75), width: 0.25)
    }
}
