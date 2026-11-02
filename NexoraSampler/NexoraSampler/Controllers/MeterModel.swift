import Foundation
import Observation
import NexoraCore

/// Schnell veränderliche Anzeigewerte (Pad-Leuchten, Schrittposition, Pegel).
/// Getrennt vom Projektmodell, damit 30-Hz-Updates nur die betroffenen Views neu zeichnen.
@MainActor
@Observable
final class MeterModel {
    var padGlow: [Double] = Array(repeating: 0, count: 16)
    var currentStep = 0
    var transport: TransportState = .stopped
    var currentPattern = 0
    var queuedPattern = -1
    /// Laufender Eintrag der Song-Kette (−1 = Song-Modus aus)
    var songIndex = -1
    var peakLeft: Float = 0
    var peakRight: Float = 0
    var activeVoices = 0
    var load: Float = 0
    var gainReduction: Float = 0
    var midiActivity = false
    var previewLevel: Float = 0

    @ObservationIgnored private var lastTriggers = Array(repeating: 0, count: 16)
    @ObservationIgnored private var flash = Array(repeating: 0.0, count: 16)
    @ObservationIgnored private var midiActivityUntil = Date.distantPast

    func update(from status: EngineStatus) {
        var glow = padGlow
        var changed = false
        for p in 0..<16 {
            let trig = status.padTriggerCount(p)
            if trig != lastTriggers[p] {
                lastTriggers[p] = trig
                flash[p] = 1
            } else {
                flash[p] = max(0, flash[p] - 0.12)
            }
            let level = Double(min(1, status.padLevel(p)))
            let value = max(flash[p], level * 0.9)
            let rounded = (value * 50).rounded() / 50
            if rounded != glow[p] { glow[p] = rounded; changed = true }
        }
        if changed { padGlow = glow }
        assign(\.currentStep, status.currentStep)
        assign(\.transport, status.transport)
        assign(\.currentPattern, status.currentPattern)
        assign(\.queuedPattern, status.queuedPattern)
        assign(\.songIndex, status.songIndex)
        assign(\.peakLeft, (status.peakLeft * 40).rounded() / 40)
        assign(\.peakRight, (status.peakRight * 40).rounded() / 40)
        assign(\.activeVoices, status.activeVoices)
        assign(\.load, (status.load * 100).rounded() / 100)
        assign(\.gainReduction, status.gainReductionDb.rounded())
        assign(\.previewLevel, (status.padLevel(16) * 20).rounded() / 20)
        assign(\.midiActivity, Date() < midiActivityUntil)
    }

    func noteMIDIActivity() {
        midiActivityUntil = Date().addingTimeInterval(0.12)
    }

    /// Setzt nur bei tatsächlicher Änderung (vermeidet unnötige View-Updates).
    private func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<MeterModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
