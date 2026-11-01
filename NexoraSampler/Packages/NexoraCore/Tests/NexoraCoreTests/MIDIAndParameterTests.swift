import XCTest
@testable import NexoraCore

final class MIDIAndParameterTests: XCTestCase {
    func testUMPParsing() {
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x2090_3C64), .noteOn(channel: 1, note: 60, velocity: 100))
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x2093_3C00), .noteOff(channel: 4, note: 60, velocity: 0), "Note-On mit Velocity 0 = Note-Off")
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x2080_2440), .noteOff(channel: 1, note: 36, velocity: 64))
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x20B1_4A7F), .controlChange(channel: 2, controller: 74, value: 127))
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x10FA_0000), .start)
        XCTAssertEqual(MIDIParser.parse(umpWord: 0x10FC_0000), .stop)
        XCTAssertNil(MIDIParser.parse(umpWord: 0x4090_3C00), "MIDI-2.0-Nachrichten werden ignoriert")
    }

    func testUMPWordSequenceSkipsMultiWordMessages() {
        // SysEx7 (2 Wörter, deren zweites Wort wie ein Note-On aussieht) gefolgt von einem echten Note-On.
        let words: [UInt32] = [0x3002_7E00, 0x2090_3C64, 0x2091_2470]
        XCTAssertEqual(MIDIParser.parse(umpWords: words), [.noteOn(channel: 2, note: 36, velocity: 112)])
        XCTAssertEqual(MIDIParser.umpWordCount(firstWord: 0x4090_0000), 2)
        XCTAssertEqual(MIDIParser.umpWordCount(firstWord: 0xF000_0000), 4)
    }

    func testByteStreamWithRunningStatus() {
        var parser = MIDIParser()
        let messages = parser.parse(bytes: [0x99, 36, 127, 38, 90, 0xF8, 36, 0, 0xB0, 1, 64])
        XCTAssertEqual(messages, [
            .noteOn(channel: 10, note: 36, velocity: 127),
            .noteOn(channel: 10, note: 38, velocity: 90),
            .clock,
            .noteOff(channel: 10, note: 36, velocity: 0),
            .controlChange(channel: 1, controller: 1, value: 64)
        ])
    }

    func testMIDISettingsLearnAndLookup() {
        var midi = MIDISettings()
        XCTAssertEqual(midi.pad(forNote: 36), 0)
        XCTAssertEqual(midi.pad(forNote: 51), 15)
        XCTAssertNil(midi.pad(forNote: 60))
        midi.learn(controller: 20, channel: 1, parameter: .reverbMix)
        midi.learn(controller: 21, channel: 1, parameter: .reverbMix)
        XCTAssertEqual(midi.ccMappings.count, 1, "Neuer Controller ersetzt altes Mapping desselben Parameters")
        XCTAssertEqual(midi.mapping(for: .reverbMix)?.controller, 21)
        midi.learn(controller: 21, channel: 1, parameter: .delayMix)
        XCTAssertEqual(midi.ccMappings.count, 1, "Controller kann nur einem Parameter zugeordnet sein")
        XCTAssertEqual(midi.mappings(controller: 21, channel: 1).first?.parameter, .delayMix)
        XCTAssertTrue(midi.mappings(controller: 21, channel: 2).isEmpty)
        midi.inputChannel = 10
        XCTAssertTrue(midi.accepts(channel: 10))
        XCTAssertFalse(midi.accepts(channel: 1))
    }

    func testParameterNormalizationRoundTrip() {
        for id in ParameterID.allCases {
            let spec = id.spec
            XCTAssertLessThan(spec.minimum, spec.maximum, "\(id)")
            XCTAssertTrue((spec.minimum...spec.maximum).contains(spec.defaultValue), "\(id) Standardwert")
            for n in [0.0, 0.25, 0.5, 0.9, 1.0] {
                let v = spec.value(fromNormalized: n)
                let back = spec.normalized(fromValue: v)
                if spec.isInteger {
                    XCTAssertEqual(spec.value(fromNormalized: back), v, "\(id)")
                } else {
                    XCTAssertEqual(back, n, accuracy: 1e-9, "\(id)")
                }
            }
            XCTAssertFalse(spec.format(spec.defaultValue).isEmpty)
        }
    }

    func testParameterAccessOnDocument() {
        var doc = ProjectDocument()
        XCTAssertEqual(doc.setValue(7, for: .padPitch, pad: 4), .pad(4))
        XCTAssertEqual(doc.pads[4].settings.pitch, 7)
        XCTAssertEqual(doc.setValue(99, for: .padPitch, pad: 4), .pad(4))
        XCTAssertEqual(doc.pads[4].settings.pitch, 24, "Begrenzung auf gültigen Bereich")
        XCTAssertEqual(doc.setValue(0.3, for: .reverbMix, pad: 0), .master)
        XCTAssertEqual(doc.master.reverbMix, 0.3)
        XCTAssertEqual(doc.setValue(133, for: .tempo, pad: 0), .tempo)
        XCTAssertEqual(doc.bpm, 133)
        doc.setValue(0.8, for: .padStart, pad: 1)
        doc.setValue(0.5, for: .padEnd, pad: 1)
        XCTAssertLessThan(doc.pads[1].settings.start, doc.pads[1].settings.end, "Start bleibt vor Ende")
        doc.master.delaySync = .eighth
        doc.setValue(0.2, for: .delayTime, pad: 0)
        XCTAssertEqual(doc.master.delaySync, .off, "Manuelle Delay-Zeit deaktiviert Tempo-Sync")
        doc.setNormalizedValue(1, for: .masterFilterCutoff, pad: 0)
        XCTAssertEqual(doc.master.filterCutoff, 20_000, accuracy: 0.01)
        XCTAssertEqual(doc.normalizedValue(of: .masterFilterCutoff, pad: 0), 1, accuracy: 1e-9)
    }

    func testParameterFormatting() {
        XCTAssertEqual(ParameterID.masterFilterCutoff.spec.format(2_400), "2.40k")
        XCTAssertEqual(ParameterID.padPan.spec.format(0), "C")
        XCTAssertEqual(ParameterID.padPan.spec.format(-0.5), "L50")
        XCTAssertEqual(ParameterID.padPitch.spec.format(-3), "-3st")
        XCTAssertEqual(ParameterID.reverbMix.spec.format(0.42), "42%")
        XCTAssertEqual(ParameterID.padAttack.spec.format(0.25), "250ms")
        XCTAssertEqual(ParameterID.masterCrushRate.spec.format(1), "OFF")
    }

    func testTempoDivisionsAndDelaySync() {
        var m = MasterSettings()
        m.delaySync = .quarter
        XCTAssertEqual(m.effectiveDelaySeconds(bpm: 120), 0.5, accuracy: 1e-9)
        m.delaySync = .dottedEighth
        XCTAssertEqual(m.effectiveDelaySeconds(bpm: 120), 0.375, accuracy: 1e-9)
        m.delaySync = .off
        m.delayTime = 0.123
        XCTAssertEqual(m.effectiveDelaySeconds(bpm: 120), 0.123)
    }

    func testFactoryKitIsComplete() {
        let sounds = FactoryKit.makeSounds()
        XCTAssertEqual(sounds.count, 16)
        for s in sounds {
            XCTAssertFalse(s.channels.isEmpty)
            XCTAssertGreaterThan(s.channels[0].count, 1000, s.name)
            let peak = s.channels.flatMap { $0 }.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.3, s.name)
            XCTAssertLessThanOrEqual(peak, 1, s.name)
            XCTAssertTrue(s.channels.allSatisfy { $0.allSatisfy(\.isFinite) }, s.name)
        }
        XCTAssertEqual(sounds[4].settings.chokeGroup, sounds[5].settings.chokeGroup, "Hi-Hats teilen eine Choke-Gruppe")
        XCTAssertFalse(FactoryKit.demoPatterns()[0].isEmpty)
    }

    func testDefaultKeyboardLayout() {
        XCTAssertEqual(PadConfig.defaultKey(for: 0), "z")
        XCTAssertEqual(PadConfig.defaultKey(for: 12), "1")
        XCTAssertEqual(Set(PadConfig.defaultKeys).count, 16)
    }
}
