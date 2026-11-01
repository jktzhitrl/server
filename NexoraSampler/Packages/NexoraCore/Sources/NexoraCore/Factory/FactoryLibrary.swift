import Foundation

public enum FactoryCategory: String, CaseIterable, Codable, Sendable {
    case kicks = "Kicks"
    case snares = "Snares"
    case claps = "Claps & Snaps"
    case hats = "Hi-Hats"
    case cymbals = "Cymbals"
    case toms = "Toms"
    case percussion = "Percussion"
    case bass = "808 & Bass"
    case synth = "Synth & Keys"
    case chords = "Chords & Stabs"
    case pads = "Pads & Atmos"
    case vocals = "Vocal Chops"
    case fx = "FX"
}

/// Ein Klang der Werks-Bibliothek.
public struct FactorySound: Sendable {
    public let id: String
    public let name: String
    public let category: FactoryCategory
    /// Empfohlene Pad-Einstellungen (z. B. Choke-Gruppe für Hi-Hats, Mono für Bässe)
    public let settings: PadSettings
    let generator: @Sendable (SoundLab) -> [[Float]]

    /// Erzeugt die Audiodaten (44,1 kHz).
    public func render(sampleRate: Double = FactoryLibrary.sampleRate) -> [[Float]] {
        // Einheitlicher 5-ms-Fade am Ende verhindert Klicks auch bei abrupt endenden Klängen.
        let fadeSamples = Int(0.005 * sampleRate)
        return SoundLab.normalize(generator(SoundLab(sampleRate: sampleRate))).map { channel in
            var c = channel
            SoundLab.fade(&c, outSamples: fadeSamples)
            return c
        }
    }

    public func makeBuffer() -> SampleBuffer {
        SampleBuffer(name: name, sampleRate: FactoryLibrary.sampleRate, channels: render())
    }
}

/// Werks-Kit: 16 Klänge aus der Bibliothek in Pad-Reihenfolge (Pad 1 = unten links).
public struct FactoryKitDefinition: Sendable {
    public let name: String
    public let soundIDs: [String]
}

/// Die eingebaute Klangbibliothek: rund 150 synthetisierte Samples in 13 Kategorien.
/// Es werden keine Audiodateien mitgeliefert – alle Klänge entstehen per Synthese.
public enum FactoryLibrary {
    public static let sampleRate: Double = 44_100
    /// Erhöhen, wenn sich Klänge ändern (führt zur Neuinstallation).
    public static let version = 1

    public static let sounds: [FactorySound] = makeSounds()

    public static func sound(id: String) -> FactorySound? { sounds.first { $0.id == id } }

    public static func sounds(in category: FactoryCategory) -> [FactorySound] {
        sounds.filter { $0.category == category }
    }

    // MARK: Werks-Kits

    public static let kits: [FactoryKitDefinition] = [
        FactoryKitDefinition(name: "House", soundIDs: [
            "kicks/House Kick", "snares/House Snare", "claps/Big Clap", "percussion/Rim Click",
            "hats/Closed Hat 1", "hats/Open Hat 1", "percussion/Shaker", "cymbals/Ride",
            "percussion/Conga High", "percussion/Conga Low", "percussion/Cowbell", "percussion/Tambourine",
            "bass/Pluck Bass C", "chords/House Organ Stab", "chords/Minor 9 Stab", "vocals/Vox Ah"]),
        FactoryKitDefinition(name: "Techno", soundIDs: [
            "kicks/Techno Rumble", "snares/Tight Snare", "claps/Warehouse Clap", "percussion/Metal Hit",
            "hats/Closed Hat 2", "hats/Open Hat 2", "hats/Ride Tick", "cymbals/Crash",
            "toms/Tom Low", "toms/Tom Mid", "percussion/Clave", "percussion/Glass Ping",
            "bass/Acid Bass C", "bass/Acid Bass G", "synth/Square Lead", "fx/Noise Riser"]),
        FactoryKitDefinition(name: "Trap", soundIDs: [
            "kicks/Trap Kick", "snares/Trap Snare", "claps/Trap Clap", "claps/Finger Snap",
            "hats/Trap Hat", "hats/Open Hat 1", "hats/Hat Roll", "cymbals/Crash",
            "bass/808 Long C", "bass/808 Long D#", "bass/808 Long F", "bass/808 Long G",
            "synth/Bell", "chords/Dark Minor", "vocals/Vox Oh", "fx/Laser"]),
        FactoryKitDefinition(name: "Lo-Fi", soundIDs: [
            "kicks/Lo-Fi Kick", "snares/Lo-Fi Snare", "snares/Brush Snare", "percussion/Rim Click",
            "hats/Dusty Hat", "hats/Open Hat 3", "percussion/Shaker", "fx/Vinyl Crackle",
            "synth/Electric Piano C", "synth/Electric Piano F", "chords/Major 7 Keys", "chords/Minor 7 Keys",
            "bass/Sub Bass C", "pads/Warm Pad", "vocals/Vox Ee", "percussion/Woodblock"]),
        FactoryKitDefinition(name: "Electro", soundIDs: [
            "kicks/Electro Kick", "snares/Electro Snare", "claps/Big Clap", "percussion/Blip",
            "hats/Closed Hat 3", "hats/Open Hat 2", "percussion/Clave", "cymbals/Splash",
            "toms/Synth Tom Low", "toms/Synth Tom Mid", "toms/Synth Tom High", "percussion/Cowbell",
            "bass/Reese Bass", "synth/Saw Lead", "fx/Zap", "fx/Siren"]),
        FactoryKitDefinition(name: "Percussion World", soundIDs: [
            "percussion/Conga Low", "percussion/Conga High", "percussion/Bongo Low", "percussion/Bongo High",
            "percussion/Shaker", "percussion/Tambourine", "percussion/Cabasa", "percussion/Triangle",
            "percussion/Clave", "percussion/Woodblock", "percussion/Cowbell", "percussion/Agogo High",
            "toms/Tom Low", "toms/Tom Mid", "toms/Tom High", "kicks/Deep Kick"])
    ]

    // MARK: Klänge

    private static func add(_ list: inout [FactorySound], _ category: FactoryCategory, _ name: String,
                            settings: (inout PadSettings) -> Void = { _ in },
                            _ generator: @escaping @Sendable (SoundLab) -> [[Float]]) {
        var s = PadSettings()
        s.volume = 0.8
        settings(&s)
        let prefix: String
        switch category {
        case .kicks: prefix = "kicks"
        case .snares: prefix = "snares"
        case .claps: prefix = "claps"
        case .hats: prefix = "hats"
        case .cymbals: prefix = "cymbals"
        case .toms: prefix = "toms"
        case .percussion: prefix = "percussion"
        case .bass: prefix = "bass"
        case .synth: prefix = "synth"
        case .chords: prefix = "chords"
        case .pads: prefix = "pads"
        case .vocals: prefix = "vocals"
        case .fx: prefix = "fx"
        }
        list.append(FactorySound(id: "\(prefix)/\(name)", name: name, category: category, settings: s, generator: generator))
    }

    // swiftlint:disable:next function_body_length
    private static func makeSounds() -> [FactorySound] {
        var l: [FactorySound] = []
        addKicks(&l)
        addSnaresAndClaps(&l)
        addHatsAndCymbals(&l)
        addTomsAndPercussion(&l)
        addBass(&l)
        addSynthsAndChords(&l)
        addPadsVocalsFX(&l)
        return l
    }

    // MARK: Kicks

    private static func kick(_ lab: SoundLab, start: Double, end: Double, pitchTau: Double, ampTau: Double,
                             length: Double, click: Double = 0.4, drive: Float = 0.15, noise: Double = 0) -> [[Float]] {
        var body = lab.osc(.sine, seconds: length, freq: { end + (start - end) * SoundLab.expDecay($0, pitchTau) },
                           amp: { SoundLab.expDecay($0, ampTau) })
        if click > 0 {
            let c = lab.filter(lab.noise(lab.frames(0.008), seed: 31), mode: .highPass, cutoff: 2_500)
            for i in c.indices { body[i] += c[i] * Float(click) * Float(1 - Double(i) / Double(c.count)) }
        }
        if noise > 0 {
            let nz = lab.filter(lab.noise(body.count, seed: 7), mode: .lowPass, cutoff: 600)
            for i in body.indices { body[i] += nz[i] * Float(noise * SoundLab.expDecay(Double(i) / lab.sampleRate, ampTau * 0.6)) }
        }
        var out = lab.drive(body, drive)
        SoundLab.fade(&out, outSamples: 200)
        return [out]
    }

    private static func addKicks(_ l: inout [FactorySound]) {
        add(&l, .kicks, "House Kick") { kick($0, start: 170, end: 52, pitchTau: 0.03, ampTau: 0.28, length: 0.55) }
        add(&l, .kicks, "Deep Kick") { kick($0, start: 120, end: 42, pitchTau: 0.05, ampTau: 0.45, length: 0.9, click: 0.2) }
        add(&l, .kicks, "Punch Kick") { kick($0, start: 220, end: 58, pitchTau: 0.02, ampTau: 0.18, length: 0.4, click: 0.7, drive: 0.4) }
        add(&l, .kicks, "Techno Rumble") { kick($0, start: 150, end: 45, pitchTau: 0.04, ampTau: 0.5, length: 1.0, click: 0.5, drive: 0.6, noise: 0.25) }
        add(&l, .kicks, "Trap Kick") { kick($0, start: 200, end: 50, pitchTau: 0.025, ampTau: 0.35, length: 0.6, click: 0.8, drive: 0.5) }
        add(&l, .kicks, "Lo-Fi Kick") { lab in
            let k = kick(lab, start: 140, end: 55, pitchTau: 0.03, ampTau: 0.22, length: 0.45, click: 0.15)
            return [lab.filter(k[0], mode: .lowPass, cutoff: 1_400)]
        }
        add(&l, .kicks, "Electro Kick") { kick($0, start: 300, end: 60, pitchTau: 0.015, ampTau: 0.2, length: 0.45, click: 0.3, drive: 0.8) }
        add(&l, .kicks, "Soft Kick") { kick($0, start: 110, end: 55, pitchTau: 0.04, ampTau: 0.25, length: 0.5, click: 0, drive: 0) }
        add(&l, .kicks, "Hard Kick") { kick($0, start: 260, end: 55, pitchTau: 0.02, ampTau: 0.3, length: 0.55, click: 1, drive: 1.2) }
        add(&l, .kicks, "Boom Kick") { kick($0, start: 90, end: 38, pitchTau: 0.08, ampTau: 0.7, length: 1.4, click: 0.1, drive: 0.2) }
        add(&l, .kicks, "Click Kick") { kick($0, start: 400, end: 70, pitchTau: 0.008, ampTau: 0.12, length: 0.3, click: 1) }
        add(&l, .kicks, "Tape Kick") { lab in
            let k = kick(lab, start: 160, end: 50, pitchTau: 0.03, ampTau: 0.3, length: 0.55, click: 0.3, drive: 0.9)
            return [lab.filter(k[0], mode: .lowPass, cutoff: 3_000)]
        }
        add(&l, .kicks, "Dub Kick") { kick($0, start: 130, end: 48, pitchTau: 0.06, ampTau: 0.4, length: 0.8, click: 0.2, drive: 0.3) }
        add(&l, .kicks, "Short Kick") { kick($0, start: 180, end: 60, pitchTau: 0.02, ampTau: 0.09, length: 0.25, click: 0.5) }
        add(&l, .kicks, "Distorted Kick") { kick($0, start: 240, end: 50, pitchTau: 0.03, ampTau: 0.35, length: 0.6, click: 0.8, drive: 2.0) }
        add(&l, .kicks, "Garage Kick") { kick($0, start: 160, end: 56, pitchTau: 0.025, ampTau: 0.2, length: 0.45, click: 0.5, drive: 0.25) }
        add(&l, .kicks, "Minimal Kick") { kick($0, start: 130, end: 60, pitchTau: 0.015, ampTau: 0.12, length: 0.3, click: 0.2, drive: 0.1) }
        add(&l, .kicks, "Rubber Kick") { kick($0, start: 100, end: 50, pitchTau: 0.09, ampTau: 0.3, length: 0.6, click: 0.1, drive: 0.3) }
    }

    // MARK: Snares & Claps

    private static func snare(_ lab: SoundLab, tone: Double, toneTau: Double, noiseTau: Double, hp: Double,
                              noiseLevel: Float = 0.9, length: Double = 0.4, seed: UInt32 = 3, lp: Double = 16_000) -> [[Float]] {
        let n = lab.frames(length)
        let t1 = lab.osc(.sine, seconds: length, freq: { tone * (1 + 0.3 * SoundLab.expDecay($0, 0.01)) }, amp: { SoundLab.expDecay($0, toneTau) })
        let t2 = lab.osc(.triangle, seconds: length, freq: { _ in tone * 1.78 }, amp: { SoundLab.expDecay($0, toneTau * 0.6) * 0.4 })
        var nz = lab.filter(lab.noise(n, seed: seed), mode: .highPass, cutoff: hp)
        if lp < 16_000 { nz = lab.filter(nz, mode: .lowPass, cutoff: lp) }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let env = Float(SoundLab.expDecay(Double(i) / lab.sampleRate, noiseTau))
            out[i] = t1[i] + t2[i] + nz[i] * noiseLevel * env
        }
        SoundLab.fade(&out)
        return lab.widen(out, amount: 0.2)
    }

    private static func clap(_ lab: SoundLab, bursts: Int, spacing: Double, center: Double, tail: Double, seed: UInt32 = 11) -> [[Float]] {
        let length = Double(bursts) * spacing + tail * 4
        let n = lab.frames(length)
        let nz = lab.filter(lab.noise(n, seed: seed), mode: .bandPass, cutoff: center, resonance: 0.45)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / lab.sampleRate
            var env = 0.0
            for b in 0..<bursts where t >= Double(b) * spacing { env = max(env, exp(-(t - Double(b) * spacing) / 0.007)) }
            let tailStart = Double(bursts) * spacing
            if t >= tailStart { env = max(env, 0.8 * exp(-(t - tailStart) / tail)) }
            out[i] = nz[i] * Float(env)
        }
        SoundLab.fade(&out)
        return lab.widen(out, amount: 0.35)
    }

    private static func addSnaresAndClaps(_ l: inout [FactorySound]) {
        add(&l, .snares, "House Snare") { snare($0, tone: 190, toneTau: 0.05, noiseTau: 0.12, hp: 1_800) }
        add(&l, .snares, "Tight Snare") { snare($0, tone: 230, toneTau: 0.03, noiseTau: 0.06, hp: 3_000, length: 0.25) }
        add(&l, .snares, "Fat Snare") { snare($0, tone: 170, toneTau: 0.08, noiseTau: 0.2, hp: 900, length: 0.5) }
        add(&l, .snares, "Trap Snare") { lab in
            let s = snare(lab, tone: 210, toneTau: 0.04, noiseTau: 0.15, hp: 1_500, length: 0.45, seed: 5)
            return s.map { lab.drive($0, 0.2) }
        }
        add(&l, .snares, "Lo-Fi Snare") { lab in
            snare(lab, tone: 180, toneTau: 0.05, noiseTau: 0.14, hp: 1_200, seed: 9).map { lab.filter($0, mode: .lowPass, cutoff: 4_500) }
        }
        add(&l, .snares, "Electro Snare") { snare($0, tone: 250, toneTau: 0.06, noiseTau: 0.1, hp: 2_500, noiseLevel: 1.1, length: 0.35, seed: 13) }
        add(&l, .snares, "Brush Snare") { lab in
            let n = lab.frames(0.5)
            var out = lab.filter(lab.noise(n, seed: 17), mode: .bandPass, cutoff: 3_500, resonance: 0.1)
            for i in out.indices {
                let t = Double(i) / lab.sampleRate
                out[i] *= Float(SoundLab.ar(t, attack: 0.02, release: 0.4, length: 0.5) * SoundLab.expDecay(t, 0.15))
            }
            return lab.widen(out, amount: 0.4)
        }
        add(&l, .snares, "Rim Snare") { snare($0, tone: 400, toneTau: 0.02, noiseTau: 0.05, hp: 4_000, noiseLevel: 0.6, length: 0.2, seed: 19) }
        add(&l, .snares, "Big Room Snare") { snare($0, tone: 200, toneTau: 0.07, noiseTau: 0.35, hp: 700, length: 0.9, seed: 23) }
        add(&l, .snares, "Snare Low Tune") { snare($0, tone: 140, toneTau: 0.09, noiseTau: 0.12, hp: 1_000, seed: 29) }
        add(&l, .snares, "Snare High Tune") { snare($0, tone: 300, toneTau: 0.04, noiseTau: 0.09, hp: 3_500, length: 0.3, seed: 37) }
        add(&l, .snares, "Crunch Snare") { lab in snare(lab, tone: 200, toneTau: 0.05, noiseTau: 0.13, hp: 1_400, seed: 39).map { lab.drive($0, 0.9) } }

        add(&l, .claps, "Big Clap") { clap($0, bursts: 3, spacing: 0.011, center: 1_200, tail: 0.12) }
        add(&l, .claps, "Warehouse Clap") { clap($0, bursts: 4, spacing: 0.013, center: 1_000, tail: 0.25, seed: 41) }
        add(&l, .claps, "Trap Clap") { clap($0, bursts: 3, spacing: 0.009, center: 1_500, tail: 0.09, seed: 43) }
        add(&l, .claps, "Tight Clap") { clap($0, bursts: 2, spacing: 0.008, center: 1_800, tail: 0.05, seed: 47) }
        add(&l, .claps, "Lo-Fi Clap") { lab in clap(lab, bursts: 3, spacing: 0.012, center: 900, tail: 0.1, seed: 53).map { lab.filter($0, mode: .lowPass, cutoff: 3_000) } }
        add(&l, .claps, "Finger Snap") { lab in
            let n = lab.frames(0.15)
            var out = lab.filter(lab.noise(n, seed: 59), mode: .bandPass, cutoff: 2_600, resonance: 0.6)
            let tone = lab.osc(.sine, seconds: 0.15, freq: { _ in 1_900 }, amp: { SoundLab.expDecay($0, 0.012) * 0.5 })
            for i in out.indices { out[i] = out[i] * Float(SoundLab.expDecay(Double(i) / lab.sampleRate, 0.018)) + tone[i] }
            return [out]
        }
    }

    // MARK: Hi-Hats & Becken

    private static func hat(_ lab: SoundLab, decay: Double, length: Double, hp: Double = 7_500, scale: Double = 1,
                            noiseMix: Float = 0.4, seed: UInt32 = 3) -> [[Float]] {
        let n = lab.frames(length)
        let metal = lab.metallic(n, scale: scale)
        let nz = lab.noise(n, seed: seed)
        var src = (0..<n).map { metal[$0] * 0.7 + nz[$0] * noiseMix }
        src = lab.filter(src, mode: .highPass, cutoff: hp, resonance: 0.2)
        for i in src.indices { src[i] *= Float(SoundLab.expDecay(Double(i) / lab.sampleRate, decay)) }
        SoundLab.fade(&src)
        return lab.widen(src, amount: 0.3)
    }

    private static func addHatsAndCymbals(_ l: inout [FactorySound]) {
        let choke: (inout PadSettings) -> Void = { $0.chokeGroup = 1 }
        add(&l, .hats, "Closed Hat 1", settings: choke) { hat($0, decay: 0.04, length: 0.12) }
        add(&l, .hats, "Closed Hat 2", settings: choke) { hat($0, decay: 0.025, length: 0.08, hp: 9_000, scale: 1.2, seed: 5) }
        add(&l, .hats, "Closed Hat 3", settings: choke) { hat($0, decay: 0.05, length: 0.14, hp: 6_500, scale: 0.9, noiseMix: 0.7, seed: 7) }
        add(&l, .hats, "Trap Hat", settings: choke) { hat($0, decay: 0.03, length: 0.1, hp: 8_500, scale: 1.1, noiseMix: 0.5, seed: 9) }
        add(&l, .hats, "Dusty Hat", settings: choke) { lab in hat(lab, decay: 0.045, length: 0.12, hp: 5_500, noiseMix: 0.9, seed: 11).map { lab.filter($0, mode: .lowPass, cutoff: 9_000) } }
        add(&l, .hats, "Pedal Hat", settings: choke) { hat($0, decay: 0.07, length: 0.18, hp: 5_000, scale: 0.85, noiseMix: 0.3, seed: 13) }
        add(&l, .hats, "Open Hat 1", settings: choke) { hat($0, decay: 0.35, length: 0.9) }
        add(&l, .hats, "Open Hat 2", settings: choke) { hat($0, decay: 0.25, length: 0.7, hp: 8_500, scale: 1.2, seed: 15) }
        add(&l, .hats, "Open Hat 3", settings: choke) { hat($0, decay: 0.5, length: 1.2, hp: 6_000, scale: 0.9, noiseMix: 0.8, seed: 17) }
        add(&l, .hats, "Ride Tick") { hat($0, decay: 0.12, length: 0.35, hp: 6_000, scale: 1.4, noiseMix: 0.15, seed: 19) }
        add(&l, .hats, "Hat Roll") { lab in
            let single = hat(lab, decay: 0.02, length: 0.06, hp: 8_500, scale: 1.1, seed: 21)[0]
            let step = lab.frames(60.0 / 140 / 8)
            var out = [Float](repeating: 0, count: step * 8 + single.count)
            for k in 0..<8 {
                let g = Float(0.45 + 0.55 * Double(k) / 7)
                for i in single.indices { out[k * step + i] += single[i] * g }
            }
            return lab.widen(out, amount: 0.3)
        }
        add(&l, .hats, "Open Hat Short", settings: choke) { hat($0, decay: 0.15, length: 0.45, hp: 7_000, scale: 1.05, seed: 25) }
        add(&l, .hats, "Shaker Hat", settings: choke) { lab in
            let n = lab.frames(0.15)
            var out = lab.filter(lab.noise(n, seed: 23), mode: .highPass, cutoff: 6_000)
            for i in out.indices { let t = Double(i) / lab.sampleRate; out[i] *= Float(SoundLab.ar(t, attack: 0.02, release: 0.1, length: 0.15)) }
            return lab.widen(out, amount: 0.4)
        }

        add(&l, .cymbals, "Crash") { hat($0, decay: 0.8, length: 2.4, hp: 3_500, scale: 0.8, noiseMix: 1.0, seed: 31) }
        add(&l, .cymbals, "Ride") { lab in
            var r = hat(lab, decay: 0.6, length: 1.8, hp: 4_000, scale: 1.5, noiseMix: 0.2, seed: 33)
            let bell = lab.osc(.sine, seconds: 1.8, freq: { _ in 2_350 }, amp: { SoundLab.expDecay($0, 0.4) * 0.15 })
            for c in r.indices { for i in r[c].indices { r[c][i] += bell[i] } }
            return r
        }
        add(&l, .cymbals, "Splash") { hat($0, decay: 0.35, length: 1.0, hp: 5_000, scale: 1.1, noiseMix: 0.9, seed: 35) }
        add(&l, .cymbals, "China") { lab in hat(lab, decay: 0.6, length: 1.8, hp: 2_500, scale: 0.6, noiseMix: 0.7, seed: 37).map { lab.drive($0, 0.4) } }
        add(&l, .cymbals, "Reverse Crash") { lab in lab.reversed(hat(lab, decay: 0.7, length: 1.6, hp: 3_500, scale: 0.8, noiseMix: 1.0, seed: 39)) }
        add(&l, .cymbals, "Long Crash") { hat($0, decay: 1.4, length: 4.0, hp: 3_000, scale: 0.75, noiseMix: 1.0, seed: 41) }
    }

    // MARK: Toms & Percussion

    private static func tom(_ lab: SoundLab, _ freq: Double, bend: Double = 0.5, tau: Double = 0.18, wave: SoundLab.Wave = .sine) -> [[Float]] {
        var out = lab.osc(wave, seconds: tau * 3, freq: { freq * (1 + bend * SoundLab.expDecay($0, 0.04)) }, amp: { SoundLab.expDecay($0, tau) })
        if wave != .sine { out = lab.filter(out, mode: .lowPass, cutoff: freq * 6) }
        SoundLab.fade(&out)
        return [out]
    }

    private static func noiseHit(_ lab: SoundLab, center: Double, q: Float, tau: Double, attack: Double = 0, length: Double, seed: UInt32) -> [[Float]] {
        let n = lab.frames(length)
        var out = lab.filter(lab.noise(n, seed: seed), mode: .bandPass, cutoff: center, resonance: q)
        for i in out.indices {
            let t = Double(i) / lab.sampleRate
            let a = attack > 0 && t < attack ? t / attack : 1
            out[i] *= Float(a * SoundLab.expDecay(max(0, t - attack), tau))
        }
        SoundLab.fade(&out)
        return lab.widen(out, amount: 0.3)
    }

    private static func addTomsAndPercussion(_ l: inout [FactorySound]) {
        add(&l, .toms, "Tom Low") { tom($0, 95) }
        add(&l, .toms, "Tom Mid") { tom($0, 140) }
        add(&l, .toms, "Tom High") { tom($0, 205) }
        add(&l, .toms, "Floor Tom") { tom($0, 72, bend: 0.4, tau: 0.3) }
        add(&l, .toms, "Synth Tom Low") { tom($0, 110, bend: 1.5, tau: 0.22, wave: .triangle) }
        add(&l, .toms, "Synth Tom Mid") { tom($0, 165, bend: 1.5, tau: 0.2, wave: .triangle) }
        add(&l, .toms, "Synth Tom High") { tom($0, 245, bend: 1.5, tau: 0.18, wave: .triangle) }
        add(&l, .toms, "Electro Tom") { tom($0, 130, bend: 2.5, tau: 0.25, wave: .square) }

        add(&l, .percussion, "Rim Click") { lab in
            [lab.osc(.sine, seconds: 0.08, freq: { _ in 1_700 }, amp: { SoundLab.expDecay($0, 0.01) * 0.6 }).enumerated().map { i, v in
                v + Float(sin(2 * .pi * 455 * Double(i) / lab.sampleRate) * SoundLab.expDecay(Double(i) / lab.sampleRate, 0.012))
            }]
        }
        add(&l, .percussion, "Clave") { $0.osc(.sine, seconds: 0.15, freq: { _ in 2_500 }, amp: { SoundLab.expDecay($0, 0.025) }).asMono }
        add(&l, .percussion, "Woodblock") { lab in [lab.filter(lab.osc(.triangle, seconds: 0.15, freq: { _ in 1_050 }, amp: { SoundLab.expDecay($0, 0.03) }), mode: .bandPass, cutoff: 1_050, resonance: 0.5)] }
        add(&l, .percussion, "Cowbell") { lab in
            let a = lab.osc(.square, seconds: 0.45, freq: { _ in 540 }, amp: { _ in 1 })
            let b = lab.osc(.square, seconds: 0.45, freq: { _ in 800 }, amp: { _ in 1 })
            var out = lab.filter(zip(a, b).map { ($0 + $1) * 0.5 }, mode: .bandPass, cutoff: 2_600, resonance: 0.3)
            for i in out.indices { let t = Double(i) / lab.sampleRate; out[i] *= Float(t < 0.02 ? 0.4 + 0.6 * SoundLab.expDecay(t, 0.01) : 0.4 * SoundLab.expDecay(t - 0.02, 0.12)) }
            return [out]
        }
        add(&l, .percussion, "Agogo High") { $0.fm(carrier: 1_250, ratio: 2.76, index: { 2 * SoundLab.expDecay($0, 0.05) }, seconds: 0.4, amp: { SoundLab.expDecay($0, 0.1) }).asMono }
        add(&l, .percussion, "Agogo Low") { $0.fm(carrier: 840, ratio: 2.76, index: { 2 * SoundLab.expDecay($0, 0.05) }, seconds: 0.45, amp: { SoundLab.expDecay($0, 0.12) }).asMono }
        add(&l, .percussion, "Conga High") { tom($0, 330, bend: 0.15, tau: 0.12) }
        add(&l, .percussion, "Conga Low") { tom($0, 220, bend: 0.15, tau: 0.16) }
        add(&l, .percussion, "Bongo High") { tom($0, 480, bend: 0.2, tau: 0.07) }
        add(&l, .percussion, "Bongo Low") { tom($0, 360, bend: 0.2, tau: 0.09) }
        add(&l, .percussion, "Shaker") { noiseHit($0, center: 7_000, q: 0.1, tau: 0.05, attack: 0.015, length: 0.18, seed: 61) }
        add(&l, .percussion, "Cabasa") { noiseHit($0, center: 9_000, q: 0.2, tau: 0.035, attack: 0.008, length: 0.14, seed: 63) }
        add(&l, .percussion, "Tambourine") { lab in
            var t = hat(lab, decay: 0.12, length: 0.4, hp: 6_500, scale: 1.6, noiseMix: 0.3, seed: 65)
            let jingle = noiseHit(lab, center: 8_000, q: 0.3, tau: 0.1, length: 0.4, seed: 67)
            for c in t.indices { for i in t[c].indices { t[c][i] += jingle[min(c, jingle.count - 1)][i] * 0.6 } }
            return t
        }
        add(&l, .percussion, "Triangle") { $0.fm(carrier: 2_800, ratio: 1.41, index: { _ in 0.4 }, seconds: 1.5, amp: { SoundLab.expDecay($0, 0.45) }).asMono }
        add(&l, .percussion, "Metal Hit") { lab in lab.widen(lab.fm(carrier: 410, ratio: 3.17, index: { 6 * SoundLab.expDecay($0, 0.08) }, seconds: 0.7, amp: { SoundLab.expDecay($0, 0.18) }), amount: 0.3) }
        add(&l, .percussion, "Glass Ping") { $0.fm(carrier: 1_760, ratio: 3.5, index: { 1.5 * SoundLab.expDecay($0, 0.1) }, seconds: 1.0, amp: { SoundLab.expDecay($0, 0.3) }).asMono }
        add(&l, .percussion, "Blip") { $0.osc(.square, seconds: 0.08, freq: { 1_800 - 900 * $0 / 0.08 }, amp: { SoundLab.expDecay($0, 0.03) * 0.6 }).asMono }
        add(&l, .percussion, "Steel Drum") { $0.fm(carrier: SoundLab.midiToHz(69), ratio: 2.0, index: { 1.8 * SoundLab.expDecay($0, 0.08) }, seconds: 1.0, amp: { SoundLab.expDecay($0, 0.3) }).asMono }
        add(&l, .percussion, "Log Drum") { lab in [lab.filter(lab.osc(.sine, seconds: 0.6, freq: { 180 * (1 + 0.05 * SoundLab.expDecay($0, 0.02)) }, amp: { SoundLab.expDecay($0, 0.15) }), mode: .lowPass, cutoff: 1_000)] }
        add(&l, .percussion, "Tabla Na") { $0.fm(carrier: 520, ratio: 1.5, index: { 2.5 * SoundLab.expDecay($0, 0.01) }, seconds: 0.5, amp: { SoundLab.expDecay($0, 0.12) }).asMono }
        add(&l, .percussion, "Snap Perc") { noiseHit($0, center: 3_200, q: 0.7, tau: 0.02, length: 0.12, seed: 69) }
        add(&l, .percussion, "Kalimba") { $0.fm(carrier: 659, ratio: 5.4, index: { 1.2 * SoundLab.expDecay($0, 0.02) }, seconds: 0.9, amp: { SoundLab.expDecay($0, 0.25) }).asMono }
    }

    // MARK: 808 & Bass

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private static func sub808(_ lab: SoundLab, note: Double, tau: Double, drive: Float) -> [[Float]] {
        let f = SoundLab.midiToHz(note)
        var out = lab.osc(.sine, seconds: tau * 3.2, freq: { f * (1 + 0.8 * SoundLab.expDecay($0, 0.025)) }, amp: { SoundLab.expDecay($0, tau) })
        out = lab.drive(out, drive)
        SoundLab.fade(&out, outSamples: 800)
        return [out]
    }

    private static func acid(_ lab: SoundLab, note: Double, saw: Bool = true) -> [[Float]] {
        let f = SoundLab.midiToHz(note)
        let raw = lab.osc(saw ? .saw : .square, seconds: 0.5, freq: { _ in f }, amp: { SoundLab.expDecay($0, 0.3) })
        var out = lab.filter(raw, mode: .lowPass, resonance: 0.85) { 200 + 3_800 * SoundLab.expDecay($0, 0.09) }
        out = lab.drive(out, 0.3)
        SoundLab.fade(&out)
        return [out]
    }

    private static func addBass(_ l: inout [FactorySound]) {
        let mono: (inout PadSettings) -> Void = { $0.mono = true }
        for (i, note) in [24.0, 27, 29, 31].enumerated() {
            let name = "808 Long " + noteNames[Int(note) % 12]
            add(&l, .bass, name, settings: mono) { sub808($0, note: note, tau: 0.8, drive: 0.35) }
            _ = i
        }
        add(&l, .bass, "808 Short", settings: mono) { sub808($0, note: 24, tau: 0.25, drive: 0.5) }
        add(&l, .bass, "808 Distorted", settings: mono) { sub808($0, note: 26, tau: 0.7, drive: 1.5) }
        add(&l, .bass, "Sub Bass C", settings: mono) { lab in
            var s = lab.osc(.sine, seconds: 1.2, freq: { _ in SoundLab.midiToHz(36) }, amp: { SoundLab.ar($0, attack: 0.005, release: 0.2, length: 1.2) })
            SoundLab.fade(&s)
            return [s]
        }
        add(&l, .bass, "Acid Bass C", settings: mono) { acid($0, note: 36) }
        add(&l, .bass, "Acid Bass G", settings: mono) { acid($0, note: 43) }
        add(&l, .bass, "Acid Square", settings: mono) { acid($0, note: 38, saw: false) }
        add(&l, .bass, "Pluck Bass C", settings: mono) { lab in
            let raw = lab.osc(.saw, seconds: 0.6, freq: { _ in SoundLab.midiToHz(36) }, amp: { SoundLab.expDecay($0, 0.35) })
            var out = lab.filter(raw, mode: .lowPass, resonance: 0.5) { 180 + 2_800 * SoundLab.expDecay($0, 0.08) }
            SoundLab.fade(&out)
            return [out]
        }
        add(&l, .bass, "Reese Bass", settings: mono) { lab in
            lab.stack(.saw, notes: [36], seconds: 1.5, voices: 4, detuneCents: 22, amp: { SoundLab.ar($0, attack: 0.01, release: 0.3, length: 1.5) })
                .map { lab.filter($0, mode: .lowPass, cutoff: 900, resonance: 0.3) }
        }
        add(&l, .bass, "FM Bass", settings: mono) { $0.fm(carrier: SoundLab.midiToHz(36), ratio: 1, index: { 4 * SoundLab.expDecay($0, 0.12) }, seconds: 0.7, amp: { SoundLab.expDecay($0, 0.35) }).asMono }
        add(&l, .bass, "Wobble Bass", settings: mono) { lab in
            let raw = lab.stack(.saw, notes: [31], seconds: 2.0, voices: 3, detuneCents: 12, amp: { SoundLab.ar($0, attack: 0.01, release: 0.2, length: 2.0) }, stereo: false)[0]
            return [lab.filter(raw, mode: .lowPass, resonance: 0.6) { 250 + 1_800 * (0.5 + 0.5 * sin(2 * .pi * 4 * $0)) }]
        }
        add(&l, .bass, "Synth Bass Square", settings: mono) { lab in
            [lab.filter(lab.osc(.square, seconds: 0.5, freq: { _ in SoundLab.midiToHz(33) }, amp: { SoundLab.expDecay($0, 0.25) }), mode: .lowPass, cutoff: 1_200, resonance: 0.3)]
        }
        add(&l, .bass, "Slap Bass", settings: mono) { $0.fm(carrier: SoundLab.midiToHz(40), ratio: 2, index: { 3 * SoundLab.expDecay($0, 0.03) }, seconds: 0.6, amp: { SoundLab.expDecay($0, 0.22) }).asMono }
    }

    // MARK: Synths & Akkorde

    private static func keysChord(_ lab: SoundLab, _ notes: [Double], tau: Double = 0.8) -> [[Float]] {
        // E-Piano-artig: FM-Glocke + Sinus je Note
        let length = tau * 3
        var left = [Float](repeating: 0, count: lab.frames(length))
        var right = left
        for (k, n) in notes.enumerated() {
            let f = SoundLab.midiToHz(n)
            let tone = lab.fm(carrier: f, ratio: 1, index: { 1.6 * SoundLab.expDecay($0, 0.15) }, seconds: length, amp: { SoundLab.expDecay($0, tau) })
            let pan = Float(k) / Float(max(notes.count - 1, 1))
            for i in tone.indices { left[i] += tone[i] * (1 - pan * 0.5); right[i] += tone[i] * (0.5 + pan * 0.5) }
        }
        SoundLab.fade(&left, outSamples: 1_000); SoundLab.fade(&right, outSamples: 1_000)
        return [left, right]
    }

    private static func sawChord(_ lab: SoundLab, _ notes: [Double], seconds: Double = 0.9, cutoff: Double = 5_000, tau: Double = 0.3,
                                 wave: SoundLab.Wave = .saw) -> [[Float]] {
        lab.stack(wave, notes: notes, seconds: seconds, voices: 2, detuneCents: 9, amp: { SoundLab.expDecay($0, tau) })
            .map { lab.filter($0, mode: .lowPass, resonance: 0.25) { 500 + cutoff * SoundLab.expDecay($0, 0.12) } }
            .map { var x = $0; SoundLab.fade(&x, outSamples: 400); return x }
    }

    private static func addSynthsAndChords(_ l: inout [FactorySound]) {
        add(&l, .synth, "Electric Piano C") { keysChord($0, [60]) }
        add(&l, .synth, "Electric Piano F") { keysChord($0, [65]) }
        add(&l, .synth, "Bell") { lab in lab.widen(lab.fm(carrier: SoundLab.midiToHz(72), ratio: 3.5, index: { 3 * SoundLab.expDecay($0, 0.4) }, seconds: 2.4, amp: { SoundLab.expDecay($0, 0.7) }), amount: 0.4) }
        add(&l, .synth, "Pluck C") { lab in
            lab.stack(.saw, notes: [60], seconds: 0.6, voices: 2, amp: { SoundLab.expDecay($0, 0.18) })
                .map { lab.filter($0, mode: .lowPass, resonance: 0.3) { 400 + 6_000 * SoundLab.expDecay($0, 0.05) } }
        }
        add(&l, .synth, "Pluck G") { lab in
            lab.stack(.saw, notes: [67], seconds: 0.6, voices: 2, amp: { SoundLab.expDecay($0, 0.18) })
                .map { lab.filter($0, mode: .lowPass, resonance: 0.3) { 400 + 6_000 * SoundLab.expDecay($0, 0.05) } }
        }
        add(&l, .synth, "Square Lead") { lab in
            [lab.filter(lab.osc(.square, seconds: 0.8, freq: { SoundLab.midiToHz(64) * (1 + 0.004 * sin(2 * .pi * 5.5 * $0)) },
                                amp: { SoundLab.ar($0, attack: 0.005, release: 0.2, length: 0.8) }), mode: .lowPass, cutoff: 3_500, resonance: 0.2)]
        }
        add(&l, .synth, "Saw Lead") { lab in
            lab.stack(.saw, notes: [64], seconds: 0.9, voices: 4, detuneCents: 14, amp: { SoundLab.ar($0, attack: 0.005, release: 0.25, length: 0.9) })
                .map { lab.filter($0, mode: .lowPass, cutoff: 5_000, resonance: 0.2) }
        }
        add(&l, .synth, "Marimba") { $0.fm(carrier: SoundLab.midiToHz(67), ratio: 4, index: { 1.2 * SoundLab.expDecay($0, 0.02) }, seconds: 0.8, amp: { SoundLab.expDecay($0, 0.2) }).asMono }
        add(&l, .synth, "Organ C") { lab in
            let f = SoundLab.midiToHz(60)
            var o = [Float](repeating: 0, count: lab.frames(1.0))
            for (h, g) in [(1.0, 1.0), (2.0, 0.6), (3.0, 0.4), (4.0, 0.25), (6.0, 0.15)] {
                let p = lab.osc(.sine, seconds: 1.0, freq: { _ in f * h }, amp: { SoundLab.ar($0, attack: 0.005, release: 0.05, length: 1.0) * g })
                for i in o.indices { o[i] += p[i] }
            }
            return lab.widen(o, amount: 0.3)
        }
        add(&l, .synth, "Electric Piano A") { keysChord($0, [57]) }
        add(&l, .synth, "Brass Stab") { lab in
            lab.stack(.saw, notes: [60, 67], seconds: 0.7, voices: 3, detuneCents: 8, amp: { SoundLab.ar($0, attack: 0.03, release: 0.2, length: 0.7) })
                .map { lab.filter($0, mode: .lowPass, resonance: 0.2) { 600 + 3_000 * min(1, $0 / 0.08) * SoundLab.expDecay($0, 0.4) } }
        }
        add(&l, .synth, "Sync Lead") { lab in
            let n = lab.frames(0.7)
            var out = [Float](repeating: 0, count: n)
            var master = 0.0, slave = 0.0
            let f = SoundLab.midiToHz(60)
            for i in 0..<n {
                let t = Double(i) / lab.sampleRate
                master += f / lab.sampleRate
                if master >= 1 { master -= 1; slave = 0 }
                slave += f * (2 + 3 * SoundLab.expDecay(t, 0.15)) / lab.sampleRate
                out[i] = Float((2 * (slave - floor(slave)) - 1) * SoundLab.ar(t, attack: 0.003, release: 0.2, length: 0.7))
            }
            return [lab.filter(out, mode: .lowPass, cutoff: 6_000)]
        }

        add(&l, .chords, "Minor 9 Stab") { sawChord($0, [57, 60, 64, 67, 71]) }
        add(&l, .chords, "Major 7 Stab") { sawChord($0, [60, 64, 67, 71]) }
        add(&l, .chords, "Minor 7 Stab") { sawChord($0, [57, 60, 64, 67]) }
        add(&l, .chords, "Sus Stab") { sawChord($0, [60, 65, 67, 72]) }
        add(&l, .chords, "Dark Minor") { sawChord($0, [51, 54, 58, 61], seconds: 1.2, cutoff: 2_500, tau: 0.5) }
        add(&l, .chords, "House Organ Stab") { sawChord($0, [60, 63, 67, 70], seconds: 0.6, cutoff: 3_500, tau: 0.2, wave: .square) }
        add(&l, .chords, "Rave Stab") { lab in sawChord(lab, [60, 63, 67, 72], seconds: 0.8, cutoff: 7_000, tau: 0.35).map { lab.drive($0, 0.4) } }
        add(&l, .chords, "Major 7 Keys") { keysChord($0, [60, 64, 67, 71], tau: 1.0) }
        add(&l, .chords, "Minor 7 Keys") { keysChord($0, [57, 60, 64, 67], tau: 1.0) }
        add(&l, .chords, "Dub Chord") { lab in sawChord(lab, [55, 58, 62], seconds: 0.5, cutoff: 1_500, tau: 0.12).map { lab.filter($0, mode: .highPass, cutoff: 250) } }
        add(&l, .chords, "Power Chord") { lab in sawChord(lab, [48, 55, 60], seconds: 1.0, cutoff: 4_000, tau: 0.6).map { lab.drive($0, 0.8) } }
    }

    // MARK: Pads, Vocals, FX

    private static func vowel(_ lab: SoundLab, _ v: Vowel, note: Double = 55, seconds: Double = 0.6) -> [[Float]] {
        let f = SoundLab.midiToHz(note)
        let source = lab.osc(.saw, seconds: seconds, freq: { f * (1 + 0.006 * sin(2 * .pi * 5 * $0)) },
                             amp: { SoundLab.ar($0, attack: 0.02, release: 0.15, length: seconds) })
        var out = [Float](repeating: 0, count: source.count)
        for (k, formant) in v.formants.enumerated() {
            let band = lab.filter(source, mode: .bandPass, cutoff: formant, resonance: 0.8)
            let gain: Float = k == 0 ? 1 : (k == 1 ? 0.6 : 0.3)
            for i in out.indices { out[i] += band[i] * gain }
        }
        return lab.widen(out, amount: 0.25)
    }

    private static func addPadsVocalsFX(_ l: inout [FactorySound]) {
        let padSettings: (inout PadSettings) -> Void = { $0.playMode = .gate; $0.release = 0.6 }
        add(&l, .pads, "Warm Pad", settings: padSettings) { lab in
            lab.stack(.saw, notes: [48, 55, 60, 64], seconds: 3.0, voices: 3, detuneCents: 12, amp: { SoundLab.ar($0, attack: 0.6, release: 1.0, length: 3.0) })
                .map { lab.filter($0, mode: .lowPass, cutoff: 1_400, resonance: 0.15) }
        }
        add(&l, .pads, "Dark Pad", settings: padSettings) { lab in
            lab.stack(.saw, notes: [45, 52, 57, 60], seconds: 3.0, voices: 3, detuneCents: 15, amp: { SoundLab.ar($0, attack: 0.8, release: 1.2, length: 3.0) })
                .map { lab.filter($0, mode: .lowPass, resonance: 0.3) { 500 + 400 * sin(2 * .pi * 0.3 * $0) } }
        }
        add(&l, .pads, "Glass Pad", settings: padSettings) { lab in
            lab.stack(.triangle, notes: [64, 71, 76, 79], seconds: 3.0, voices: 2, detuneCents: 6, amp: { SoundLab.ar($0, attack: 0.4, release: 1.2, length: 3.0) })
        }
        add(&l, .pads, "Drone", settings: padSettings) { lab in
            lab.stack(.saw, notes: [36, 43], seconds: 4.0, voices: 4, detuneCents: 18, amp: { SoundLab.ar($0, attack: 1.0, release: 1.5, length: 4.0) })
                .map { lab.filter($0, mode: .lowPass, resonance: 0.4) { 300 + 900 * (0.5 + 0.5 * sin(2 * .pi * 0.15 * $0)) } }
        }
        add(&l, .pads, "Wind") { lab in
            let n = lab.frames(3.0)
            let nz = lab.filter(lab.noise(n, seed: 71), mode: .bandPass, resonance: 0.7) { 600 + 900 * (0.5 + 0.5 * sin(2 * .pi * 0.4 * $0)) }
            var out = nz
            for i in out.indices { out[i] *= Float(SoundLab.ar(Double(i) / lab.sampleRate, attack: 0.8, release: 1.0, length: 3.0)) }
            return lab.widen(out, amount: 0.6)
        }
        add(&l, .pads, "Strings") { lab in
            lab.stack(.saw, notes: [55, 62, 67, 71], seconds: 2.5, voices: 4, detuneCents: 10, amp: { SoundLab.ar($0, attack: 0.3, release: 0.8, length: 2.5) })
                .map { lab.filter($0, mode: .lowPass, cutoff: 3_000, resonance: 0.1) }
        }

        for (v, label) in [(Vowel.a, "Ah"), (.e, "Eh"), (.i, "Ee"), (.o, "Oh"), (.u, "Oo")] {
            add(&l, .vocals, "Vox \(label)") { vowel($0, v) }
        }
        add(&l, .vocals, "Vox Ah High") { vowel($0, .a, note: 67, seconds: 0.5) }
        add(&l, .vocals, "Vox Choir") { lab in
            var sum: [[Float]] = vowel(lab, .o, note: 55, seconds: 1.5)
            for n in [59.0, 62.0] {
                let v = vowel(lab, .o, note: n, seconds: 1.5)
                for c in sum.indices { for i in sum[c].indices { sum[c][i] += v[min(c, v.count - 1)][i] } }
            }
            return sum
        }
        add(&l, .vocals, "Vox Stutter") { lab in
            let syl = vowel(lab, .a, note: 60, seconds: 0.09)[0]
            let step = lab.frames(0.12)
            var out = [Float](repeating: 0, count: step * 4)
            for k in 0..<4 { for i in syl.indices where k * step + i < out.count { out[k * step + i] += syl[i] } }
            return lab.widen(out, amount: 0.25)
        }

        add(&l, .fx, "Zap") { $0.osc(.sine, seconds: 0.3, freq: { 80 + 2_400 * SoundLab.expDecay($0, 0.04) }, amp: { SoundLab.expDecay($0, 0.1) }).asMono }
        add(&l, .fx, "Laser") { lab in lab.widen(lab.osc(.square, seconds: 0.4, freq: { 3_000 * SoundLab.expDecay($0, 0.08) + 150 }, amp: { SoundLab.expDecay($0, 0.15) * 0.5 }), amount: 0.4) }
        add(&l, .fx, "Noise Riser") { lab in
            let n = lab.frames(2.0)
            var out = lab.filter(lab.noise(n, seed: 81), mode: .bandPass, resonance: 0.5) { 300 * pow(30, $0 / 2.0) }
            for i in out.indices { let t = Double(i) / lab.sampleRate; out[i] *= Float(pow(t / 2.0, 2)) }
            SoundLab.fade(&out, outSamples: 300)
            return lab.widen(out, amount: 0.6)
        }
        add(&l, .fx, "Downlifter") { lab in
            let n = lab.frames(2.0)
            var out = lab.filter(lab.noise(n, seed: 83), mode: .bandPass, resonance: 0.5) { 9_000 * pow(0.03, $0 / 2.0) }
            for i in out.indices { out[i] *= Float(SoundLab.expDecay(Double(i) / lab.sampleRate, 0.7)) }
            return lab.widen(out, amount: 0.6)
        }
        add(&l, .fx, "Impact") { lab in
            let boom = kick(lab, start: 90, end: 30, pitchTau: 0.1, ampTau: 0.8, length: 2.0, click: 0.6, drive: 0.6, noise: 0.5)[0]
            let crash = hat(lab, decay: 0.6, length: 2.0, hp: 3_000, scale: 0.7, noiseMix: 1.0, seed: 85)
            return crash.map { c in zip(boom, c).map { $0 + $1 * 0.5 } }
        }
        add(&l, .fx, "Reverse Swell") { lab in
            lab.reversed(lab.stack(.saw, notes: [60, 64, 67], seconds: 1.5, voices: 2, amp: { SoundLab.expDecay($0, 0.5) })
                .map { lab.filter($0, mode: .lowPass, cutoff: 3_000) })
        }
        add(&l, .fx, "Vinyl Crackle") { lab in
            let n = lab.frames(3.0)
            var rng = FastRandom(seed: 87)
            var out = lab.filter(lab.noise(n, seed: 89), mode: .lowPass, cutoff: 2_000).map { $0 * 0.04 }
            for i in 0..<n where rng.nextUInt32() % 2_200 == 0 {
                let amp = Float(rng.nextBipolar()) * 0.9
                for k in 0..<min(30, n - i) { out[i + k] += amp * Float(SoundLab.expDecay(Double(k), 4)) }
            }
            return lab.widen(out, amount: 0.5)
        }
        add(&l, .fx, "Siren") { lab in lab.widen(lab.osc(.triangle, seconds: 2.0, freq: { 700 + 400 * sin(2 * .pi * 1.5 * $0) }, amp: { SoundLab.ar($0, attack: 0.05, release: 0.3, length: 2.0) * 0.6 }), amount: 0.3) }
        add(&l, .fx, "UFO") { lab in lab.widen(lab.fm(carrier: 600, ratio: 0.51, index: { 5 + 3 * sin(2 * .pi * 3 * $0) }, seconds: 2.0, amp: { SoundLab.ar($0, attack: 0.2, release: 0.5, length: 2.0) }), amount: 0.5) }
        add(&l, .fx, "Glitch") { lab in
            let n = lab.frames(0.5)
            var rng = FastRandom(seed: 91)
            var out = [Float](repeating: 0, count: n)
            var i = 0
            while i < n {
                let len = Int(rng.nextUInt32() % 1_500) + 200
                let f = Double(rng.nextUInt32() % 3_000 + 100)
                for k in 0..<min(len, n - i) { out[i + k] = Float(SoundLab.wave(.square, f * Double(k) / lab.sampleRate)) * 0.5 }
                i += len + Int(rng.nextUInt32() % 800)
            }
            SoundLab.fade(&out)
            return lab.widen(out, amount: 0.4)
        }
        add(&l, .fx, "White Noise Burst") { noiseHit($0, center: 5_000, q: 0, tau: 0.15, length: 0.5, seed: 93) }
        add(&l, .fx, "Sub Drop") { lab in
            var s = lab.osc(.sine, seconds: 1.5, freq: { 120 * pow(0.25, $0 / 1.5) }, amp: { SoundLab.expDecay($0, 0.8) })
            SoundLab.fade(&s, outSamples: 500)
            return [s]
        }
        add(&l, .fx, "Coin") { lab in
            let n = lab.frames(0.35)
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let t = Double(i) / lab.sampleRate
                let f = t < 0.07 ? 988.0 : 1_319.0
                out[i] = Float(SoundLab.wave(.square, f * t) * SoundLab.expDecay(max(0, t - 0.07), 0.12) * 0.5)
            }
            SoundLab.fade(&out)
            return [out]
        }
    }
}

private extension Array where Element == Float {
    var asMono: [[Float]] { [self] }
}
