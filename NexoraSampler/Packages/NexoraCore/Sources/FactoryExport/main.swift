import Foundation
import NexoraCore

// Schreibt alle Werks-Klänge (Bibliothek + klassisches Werks-Kit) als 16-Bit-WAV sowie
// ein Manifest (Kategorien, Pad-Einstellungen, Kits, Demo-Patterns) in einen Ordner.
// Verwendung: swift run -c release FactoryExport <Zielordner>

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Verwendung: FactoryExport <Zielordner>")
    exit(1)
}
let root = URL(fileURLWithPath: args[1], isDirectory: true)
let fm = FileManager.default
try? fm.removeItem(at: root)
try fm.createDirectory(at: root, withIntermediateDirectories: true)

func safeName(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
}

func write(_ channels: [[Float]], to url: URL) throws {
    let left = channels[0]
    let right = channels.count > 1 ? channels[1] : channels[0]
    try AudioFileWriter.write(left: left, right: right, sampleRate: FactoryLibrary.sampleRate,
                              format: .wav, bitDepth: .pcm16, to: url, mono: channels.count == 1)
}

struct SoundEntry: Encodable {
    let id: String
    let name: String
    let category: String
    let file: String
    let channels: Int
    let duration: Double
    let settings: PadSettings
}
struct KitEntry: Encodable { let name: String; let soundIDs: [String] }
struct ClassicPad: Encodable { let name: String; let file: String; let settings: PadSettings }
struct Manifest: Encodable {
    let version: Int
    let sampleRate: Double
    let categories: [String]
    let sounds: [SoundEntry]
    let kits: [KitEntry]
    let classicKitName: String
    let classicKit: [ClassicPad]
    let demoPatterns: [SequencerPattern]
}

var sounds: [SoundEntry] = []
for sound in FactoryLibrary.sounds {
    let dir = root.appendingPathComponent(safeName(sound.category.rawValue), isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let channels = sound.render()
    let rel = safeName(sound.category.rawValue) + "/" + safeName(sound.name) + ".wav"
    try write(channels, to: root.appendingPathComponent(rel))
    sounds.append(SoundEntry(id: sound.id, name: sound.name, category: sound.category.rawValue, file: rel,
                             channels: channels.count, duration: Double(channels[0].count) / FactoryLibrary.sampleRate,
                             settings: sound.settings))
}

let classicDir = root.appendingPathComponent("Classic", isDirectory: true)
try fm.createDirectory(at: classicDir, withIntermediateDirectories: true)
var classic: [ClassicPad] = []
for sound in FactoryKit.makeSounds() {
    let rel = "Classic/" + safeName(sound.name) + ".wav"
    try write(sound.channels, to: root.appendingPathComponent(rel))
    classic.append(ClassicPad(name: sound.name, file: rel, settings: sound.settings))
}

let manifest = Manifest(version: FactoryLibrary.version, sampleRate: FactoryLibrary.sampleRate,
                        categories: FactoryCategory.allCases.map(\.rawValue), sounds: sounds,
                        kits: FactoryLibrary.kits.map { KitEntry(name: $0.name, soundIDs: $0.soundIDs) },
                        classicKitName: FactoryKit.kitName, classicKit: classic,
                        demoPatterns: FactoryKit.demoPatterns())
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
print("Exportiert: \(sounds.count) Bibliotheksklänge, \(classic.count) Werks-Kit-Klänge → \(root.path)")
