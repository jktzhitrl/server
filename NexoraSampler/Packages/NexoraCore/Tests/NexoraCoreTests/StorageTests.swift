import XCTest
@testable import NexoraCore

final class StorageTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = TestAudio.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func sampleFile(named name: String, frames: Int = 1000) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let data = TestAudio.sine(frequency: 440, seconds: Double(frames) / 44_100)
        try AudioFileWriter.write(left: data, right: data, sampleRate: 44_100, format: .wav, bitDepth: .pcm16, to: url)
        return url
    }

    func testProjectJSONRoundTrip() throws {
        var doc = ProjectDocument(name: "Test")
        doc.bpm = 97.5
        doc.swing = 58
        doc.pads[3].name = "MY SNARE"
        doc.pads[3].settings.pitch = -5
        doc.pads[3].settings.reverse = true
        doc.pads[3].settings.playMode = .loop
        doc.master.reverbMix = 0.4
        doc.master.modTarget = .vibrato
        doc.sequencer.patterns[2].toggle(track: 5, step: 9)
        doc.sequencer.trackMutes[4] = true
        doc.midi.learn(controller: 74, channel: 1, parameter: .masterFilterCutoff)
        doc.xyPad = XYPadAssignment(x: .delayFeedback, y: .masterDrive)
        let data = try SamplePackager.encoder.encode(doc)
        let decoded = try SamplePackager.decoder.decode(ProjectDocument.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.bpm, 97.5)
        XCTAssertEqual(decoded.pads[3], doc.pads[3])
        XCTAssertEqual(decoded.master, doc.master)
        XCTAssertEqual(decoded.sequencer, doc.sequencer)
        XCTAssertEqual(decoded.midi, doc.midi)
        XCTAssertEqual(decoded.xyPad, doc.xyPad)
    }

    func testDecodingToleratesMissingAndUnknownKeys() throws {
        let json = """
        {"formatVersion":1,"name":"Old","bpm":130,
         "pads":[{"index":2,"name":"X","settings":{"volume":0.5,"futureKey":123}}],
         "unknownTopLevel":{"a":1}}
        """
        let doc = try SamplePackager.decoder.decode(ProjectDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.name, "Old")
        XCTAssertEqual(doc.bpm, 130)
        XCTAssertEqual(doc.pads.count, 16, "Fehlende Pads werden ergänzt")
        XCTAssertEqual(doc.pads[2].name, "X")
        XCTAssertEqual(doc.pads[2].settings.volume, 0.5)
        XCTAssertEqual(doc.pads[2].settings.pitch, 0, "Fehlende Felder erhalten Standardwerte")
        XCTAssertEqual(doc.sequencer.patterns.count, SequencerState.patternSlots)
        XCTAssertEqual(doc.pads[2].keyboardKey, PadConfig.defaultKey(for: 2))
    }

    func testNewerFormatVersionIsRejected() {
        let json = #"{"formatVersion": 99, "name": "Future"}"#
        XCTAssertThrowsError(try SamplePackager.decoder.decode(ProjectDocument.self, from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? ProjectError, .unsupportedVersion(99))
        }
    }

    func testProjectPackageWriteAndRead() throws {
        let source = try sampleFile(named: "My Kick.wav")
        var doc = ProjectDocument(name: "Beat")
        doc.pads[0].sample = SampleReference(fileName: "My Kick.wav", originalPath: source.path)
        doc.pads[0].name = "KICK"
        let generated = SampleBuffer(name: "SYNTH", sampleRate: 48_000, channels: [TestAudio.constant(0.25, frames: 480)])
        var sources = [PadSampleSource](repeating: .none, count: 16)
        sources[0] = .file(source)
        sources[1] = .buffer(generated)
        let packageURL = dir.appendingPathComponent("Beat.nexora")
        let saved = try ProjectPackage.write(doc, sources: sources, to: packageURL)

        XCTAssertTrue(ProjectPackage.isProjectPackage(packageURL))
        XCTAssertEqual(saved.pads[0].sample?.packagePath, "Samples/01-My Kick.wav")
        XCTAssertEqual(saved.pads[1].sample?.packagePath, "Samples/02-SYNTH.wav")
        XCTAssertNil(saved.pads[2].sample)

        let loaded = try ProjectPackage.read(from: packageURL)
        XCTAssertEqual(loaded.pads[0].name, "KICK")
        let resolver = SampleResolver()
        let kickURL = try XCTUnwrap(resolver.resolve(loaded.pads[0].sample!, packageURL: packageURL))
        XCTAssertTrue(kickURL.path.hasPrefix(packageURL.path))
        let synthURL = try XCTUnwrap(resolver.resolve(loaded.pads[1].sample!, packageURL: packageURL))
        let decoded = try AudioFileReader.read(url: synthURL)
        XCTAssertEqual(decoded.sampleRate, 48_000)
        XCTAssertEqual(decoded.channels[0].count, 480)
        XCTAssertEqual(decoded.channels[0][100], 0.25, accuracy: 1e-6, "Float-WAV ist verlustfrei")

        // Projekt verschieben: Samples werden weiterhin im Paket gefunden.
        let moved = dir.appendingPathComponent("Moved.nexora")
        try FileManager.default.moveItem(at: packageURL, to: moved)
        try FileManager.default.removeItem(at: source)
        let reloaded = try ProjectPackage.read(from: moved)
        XCTAssertNotNil(resolver.resolve(reloaded.pads[0].sample!, packageURL: moved))
    }

    func testOverwritingPackageKeepsSamplesFromOldPackage() throws {
        let source = try sampleFile(named: "Snare.wav")
        let packageURL = dir.appendingPathComponent("P.nexora")
        var sources = [PadSampleSource](repeating: .none, count: 16)
        sources[0] = .file(source)
        let first = try ProjectPackage.write(ProjectDocument(name: "P"), sources: sources, to: packageURL)
        try FileManager.default.removeItem(at: source)
        // Zweites Speichern: Quelle ist jetzt die Kopie im bestehenden Paket.
        let inPackage = packageURL.appendingPathComponent(first.pads[0].sample!.packagePath!)
        sources[0] = .file(inPackage)
        var doc = first
        doc.bpm = 140
        try ProjectPackage.write(doc, sources: sources, to: packageURL)
        let loaded = try ProjectPackage.read(from: packageURL)
        XCTAssertEqual(loaded.bpm, 140)
        XCTAssertNotNil(SampleResolver().resolve(loaded.pads[0].sample!, packageURL: packageURL))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "Keine temporären Ordner zurückgelassen")
    }

    func testSampleResolverFallbackOrder() throws {
        let original = try sampleFile(named: "Hat.wav")
        var ref = SampleReference(fileName: "Hat.wav", originalPath: original.path)
        XCTAssertEqual(SampleResolver().resolveWithLocation(ref, packageURL: nil)?.location, .originalPath)

        // Original verschoben → Suche nach Dateiname in Suchordnern
        let sub = dir.appendingPathComponent("Library/Drums", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let movedURL = sub.appendingPathComponent("Hat.wav")
        try FileManager.default.moveItem(at: original, to: movedURL)
        let searching = SampleResolver(searchDirectories: [dir])
        let found = searching.resolveWithLocation(ref, packageURL: nil)
        XCTAssertEqual(found?.location, .search)
        XCTAssertEqual(found?.url.standardizedFileURL.path, movedURL.standardizedFileURL.path)

        // Bookmark hat Vorrang vor Pfad
        ref.bookmark = Data([1, 2, 3])
        let withBookmark = SampleResolver(bookmarkResolver: { _ in movedURL })
        XCTAssertEqual(withBookmark.resolveWithLocation(ref, packageURL: nil)?.location, .bookmark)

        // Bibliothek hat Vorrang vor Bookmark
        ref.libraryItemID = UUID()
        let withLibrary = SampleResolver(bookmarkResolver: { _ in nil }, libraryLookup: { _ in movedURL })
        XCTAssertEqual(withLibrary.resolveWithLocation(ref, packageURL: nil)?.location, .library)

        XCTAssertNil(SampleResolver().resolve(SampleReference(fileName: "missing.wav"), packageURL: nil))
    }

    func testPresetStoreKitsEffectsPatterns() throws {
        let store = PresetStore(root: dir.appendingPathComponent("Presets"))
        var pads = ProjectDocument().pads
        pads[0].name = "BOOM"
        pads[0].settings.drive = 0.3
        var sources = [PadSampleSource](repeating: .none, count: 16)
        sources[0] = .buffer(SampleBuffer(name: "BOOM", sampleRate: 44_100, channels: [TestAudio.constant(0.1, frames: 100)]))
        let kitURL = try store.saveKit(name: "My Kit", pads: pads, sources: sources)
        XCTAssertEqual(store.list(.kit).map(\.name), ["My Kit"])
        let kit = try store.loadKit(at: kitURL)
        XCTAssertEqual(kit.pads[0].name, "BOOM")
        XCTAssertEqual(kit.pads[0].settings.drive, 0.3)
        XCTAssertNotNil(SampleResolver().resolve(kit.pads[0].sample!, packageURL: kitURL))

        var master = MasterSettings()
        master.delayMix = 0.6
        let fxURL = try store.saveEffects(name: "Dub", master: master)
        XCTAssertEqual(try store.loadEffects(at: fxURL).master.delayMix, 0.6)

        var pattern = SequencerPattern(name: "x")
        pattern.toggle(track: 0, step: 3)
        let patURL = try store.savePattern(name: "Groove", pattern: pattern, bpm: 90, swing: 60)
        let loaded = try store.loadPattern(at: patURL)
        XCTAssertTrue(loaded.pattern[0, 3].active)
        XCTAssertEqual(loaded.pattern.name, "Groove")
        XCTAssertEqual(loaded.bpm, 90)

        try store.delete(store.list(.effects)[0])
        XCTAssertTrue(store.list(.effects).isEmpty)
    }

    func testSampleLibraryPersistence() throws {
        let root = dir.appendingPathComponent("Library")
        let library = SampleLibrary(root: root)
        let collection = try library.createCollection(name: "Drums")
        let file = try sampleFile(named: "Clap.wav")
        let item = try library.importFile(file, into: collection.id, copy: true, duration: 0.1, sampleRate: 44_100, channels: 2)
        let copied = try XCTUnwrap(library.url(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertTrue(copied.path.hasPrefix(root.path))
        // Gleicher Name erneut → eindeutiger Dateiname
        let second = try library.importFile(file, into: collection.id, copy: true, duration: 0.1, sampleRate: 44_100, channels: 2)
        XCTAssertNotEqual(library.url(for: second), copied)
        try library.renameItem(item.id, to: "Big Clap")

        let reopened = SampleLibrary(root: root)
        let drums = try XCTUnwrap(reopened.collections.first { $0.name == "Drums" })
        XCTAssertEqual(drums.items.count, 2)
        XCTAssertEqual(drums.items.first?.name, "Big Clap")
        XCTAssertEqual(reopened.url(forItemID: item.id), copied)

        try reopened.removeItem(second.id, deleteFile: true)
        XCTAssertNil(reopened.item(withID: second.id))
        try reopened.removeCollection(drums.id, deleteFiles: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertFalse(reopened.collections.isEmpty, "Es bleibt immer eine Bibliothek bestehen")
    }

    func testLoaderReadsWavAndAiff() throws {
        let wav = try sampleFile(named: "a.wav", frames: 2000)
        let buffer = try AudioFileLoader.load(url: wav)
        XCTAssertEqual(buffer.frameCount, 2000)
        XCTAssertEqual(buffer.sampleRate, 44_100)
        XCTAssertTrue(buffer.isStereo)
        let aiff = dir.appendingPathComponent("b.aif")
        try AudioFileWriter.write(left: TestAudio.constant(0.5, frames: 300), right: TestAudio.constant(-0.5, frames: 300),
                                  sampleRate: 48_000, format: .aiff, bitDepth: .pcm24, to: aiff)
        let b = try AudioFileLoader.load(url: aiff)
        XCTAssertEqual(b.sampleRate, 48_000)
        XCTAssertEqual(b.channelData()[1][10], -0.5, accuracy: 0.0001)
        XCTAssertThrowsError(try AudioFileLoader.load(url: dir.appendingPathComponent("x.txt")))
    }
}
