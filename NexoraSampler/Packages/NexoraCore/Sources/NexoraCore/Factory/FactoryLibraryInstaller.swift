import Foundation

/// Installiert die Werks-Bibliothek als WAV-Dateien in die Sample-Bibliothek
/// (eine Sammlung „Factory · <Kategorie>“ je Kategorie). Danach stehen alle Klänge im
/// Sample-Browser zum Vorhören, Ziehen auf Pads und Speichern in Projekten bereit.
public enum FactoryLibraryInstaller {
    public static let collectionPrefix = "Factory · "
    static let versionFileName = "factory-version.txt"

    public static func installedVersion(in library: SampleLibrary) -> Int? {
        let url = library.root.appendingPathComponent(versionFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `true`, wenn die aktuelle Version vollständig installiert ist.
    public static func isInstalled(in library: SampleLibrary) -> Bool {
        guard installedVersion(in: library) == FactoryLibrary.version else { return false }
        let count = library.collections.filter(\.isFactory).reduce(0) { $0 + $1.items.count }
        return count == FactoryLibrary.sounds.count
    }

    /// Erzeugt alle Klänge und schreibt sie in die Bibliothek. Ältere Werks-Sammlungen werden ersetzt;
    /// eigene Sammlungen des Benutzers bleiben unberührt.
    /// - Parameter progress: 0 ... 1
    public static func install(into library: SampleLibrary, progress: ((Double) -> Void)? = nil) throws {
        library.removeFactoryCollections()
        var collectionIDs: [FactoryCategory: UUID] = [:]
        for category in FactoryCategory.allCases {
            let c = SampleLibraryCollection(name: collectionPrefix + category.rawValue, isFactory: true)
            library.appendCollection(c)
            collectionIDs[category] = c.id
        }
        let total = FactoryLibrary.sounds.count
        for (index, sound) in FactoryLibrary.sounds.enumerated() {
            let channels = sound.render()
            let left = channels[0]
            let right = channels.count > 1 ? channels[1] : channels[0]
            let data = try AudioFileWriter.encode(left: left, right: right, sampleRate: FactoryLibrary.sampleRate,
                                                  format: .wav, bitDepth: .pcm24, dither: false)
            let fileName = SamplePackager.sanitize(sound.name) + ".wav"
            _ = try library.addGeneratedItem(name: sound.name, fileName: fileName, data: data,
                                             into: collectionIDs[sound.category]!,
                                             duration: Double(left.count) / FactoryLibrary.sampleRate,
                                             sampleRate: FactoryLibrary.sampleRate, channels: channels.count)
            progress?(Double(index + 1) / Double(total))
        }
        try library.save()
        try String(FactoryLibrary.version).write(to: library.root.appendingPathComponent(versionFileName),
                                                 atomically: true, encoding: .utf8)
    }
}
