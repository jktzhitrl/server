import XCTest
@testable import NexoraCore

final class FactoryLibraryTests: XCTestCase {
    func testLibrarySizeAndCategories() {
        let sounds = FactoryLibrary.sounds
        XCTAssertGreaterThanOrEqual(sounds.count, 140)
        XCTAssertEqual(Set(sounds.map(\.id)).count, sounds.count, "IDs sind eindeutig")
        for category in FactoryCategory.allCases {
            XCTAssertGreaterThanOrEqual(FactoryLibrary.sounds(in: category).count, 5, category.rawValue)
        }
    }

    func testEverySoundRendersValidAudio() {
        for sound in FactoryLibrary.sounds {
            let channels = sound.render()
            XCTAssertFalse(channels.isEmpty, sound.id)
            XCTAssertLessThanOrEqual(channels.count, 2, sound.id)
            let frames = channels[0].count
            XCTAssertTrue(channels.allSatisfy { $0.count == frames }, sound.id)
            let duration = Double(frames) / FactoryLibrary.sampleRate
            XCTAssertGreaterThan(duration, 0.05, sound.id)
            XCTAssertLessThanOrEqual(duration, 4.5, sound.id)
            let all = channels.flatMap { $0 }
            XCTAssertTrue(all.allSatisfy(\.isFinite), sound.id)
            let peak = all.map(abs).max() ?? 0
            XCTAssertEqual(peak, 0.89, accuracy: 0.01, "\(sound.id) ist normalisiert")
            XCTAssertGreaterThan(TestAudio.rms(channels[0]), 0.005, "\(sound.id) ist hörbar")
            // Kein Klick am Ende: letzte Samples nahe null
            XCTAssertLessThan(abs(channels[0].last ?? 0), 0.05, "\(sound.id) endet ohne Klick")
        }
    }

    func testRenderingIsDeterministic() {
        let s = FactoryLibrary.sound(id: "fx/Glitch")!
        XCTAssertEqual(s.render(), s.render())
    }

    func testKitsReferenceExistingSounds() {
        XCTAssertGreaterThanOrEqual(FactoryLibrary.kits.count, 5)
        for kit in FactoryLibrary.kits {
            XCTAssertEqual(kit.soundIDs.count, 16, kit.name)
            for id in kit.soundIDs { XCTAssertNotNil(FactoryLibrary.sound(id: id), "\(kit.name): \(id)") }
        }
    }

    func testBassSoundsHaveExpectedPitch() {
        // 808 Long C = C1 (32,7 Hz) – Grundfrequenz über Nulldurchgänge im stationären Teil
        let x = FactoryLibrary.sound(id: "bass/808 Long C")!.render()[0]
        let segment = Array(x[22_050..<44_100])
        var crossings = 0
        for i in 1..<segment.count where (segment[i - 1] < 0) != (segment[i] < 0) { crossings += 1 }
        XCTAssertEqual(Double(crossings) / 2 / 0.5, 32.7, accuracy: 2)
    }

    func testInstallerWritesLibraryAndIsIdempotent() throws {
        let root = TestAudio.temporaryDirectory().appendingPathComponent("Library")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let library = SampleLibrary(root: root)
        let user = try library.createCollection(name: "Meine Drums")
        XCTAssertFalse(FactoryLibraryInstaller.isInstalled(in: library))
        var lastProgress = 0.0
        try FactoryLibraryInstaller.install(into: library) { lastProgress = $0 }
        XCTAssertEqual(lastProgress, 1)
        XCTAssertTrue(FactoryLibraryInstaller.isInstalled(in: library))
        let factory = library.collections.filter(\.isFactory)
        XCTAssertEqual(factory.count, FactoryCategory.allCases.count)
        XCTAssertEqual(factory.reduce(0) { $0 + $1.items.count }, FactoryLibrary.sounds.count)

        // Datei existiert, ist lesbar und hat die richtige Länge
        let kick = try XCTUnwrap(library.factoryItem(category: FactoryCategory.kicks.rawValue, name: "House Kick"))
        let url = try XCTUnwrap(library.url(for: kick))
        let decoded = try AudioFileReader.read(url: url)
        XCTAssertEqual(decoded.sampleRate, 44_100)
        XCTAssertEqual(Double(decoded.channels[0].count) / 44_100, kick.duration, accuracy: 0.001)

        // Neu geöffnet: noch installiert, Benutzer-Sammlung unverändert
        let reopened = SampleLibrary(root: root)
        XCTAssertTrue(FactoryLibraryInstaller.isInstalled(in: reopened))
        XCTAssertTrue(reopened.collections.contains { $0.id == user.id })

        // Neuinstallation ersetzt statt zu verdoppeln
        try FactoryLibraryInstaller.install(into: reopened)
        XCTAssertEqual(reopened.collections.filter(\.isFactory).count, FactoryCategory.allCases.count)
        XCTAssertTrue(reopened.collections.contains { $0.id == user.id })
    }

    func testOldLibraryIndexWithoutFactoryFlagStillLoads() throws {
        let root = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let json = #"{"formatVersion":1,"collections":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Alt","items":[]}]}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("library.json"))
        let lib = SampleLibrary(root: root)
        XCTAssertEqual(lib.collections.first?.name, "Alt")
        XCTAssertEqual(lib.collections.first?.isFactory, false)
    }
}
