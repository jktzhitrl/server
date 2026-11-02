import Foundation

public enum TransportCommand: Sendable {
    case play, pause, stop
}

/// Befehle an die Audio-Engine. Sie werden thread-sicher eingereiht und zu Beginn
/// des nächsten Audio-Blocks im Audio-Thread ausgeführt.
public enum EngineCommand {
    case noteOn(pad: Int, velocity: Float)
    /// Note mit Transposition in Halbtönen (Keyboard-Modus der Pads)
    case noteOnTransposed(pad: Int, velocity: Float, semitones: Double)
    case noteOff(pad: Int)
    case allNotesOff
    case setSample(pad: Int, sample: SampleBuffer?)
    case setPadSettings(pad: Int, settings: PadSettings)
    case setMaster(MasterSettings)
    case setEngineSettings(EngineSettings)
    case setPattern(slot: Int, pattern: PatternSnapshot?)
    case selectPattern(slot: Int, immediately: Bool)
    case setTempo(bpm: Double, swing: Double)
    case setTrackStates(mutes: UInt16, solos: UInt16)
    case transport(TransportCommand)
    case setRecording(Bool)
    case setMetronome(Bool)
    case preview(sample: SampleBuffer?, gain: Float)
}

/// Rückmeldungen der Engine an die Benutzeroberfläche.
public enum EngineEvent: Sendable {
    /// Ein live gespieltes Pad während der Aufnahme.
    /// `positionInPattern` in Schritten (0 ..< `patternLength`, mit Nachkommaanteil).
    case recordedHit(pad: Int, velocity: Float, slot: Int, positionInPattern: Double, patternLength: Int)
}
