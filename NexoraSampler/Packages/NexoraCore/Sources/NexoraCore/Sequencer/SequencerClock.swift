import Foundation

/// Ein vom Sequencer geplantes Ereignis. Zeiten in Sequencer-Schritten (16tel)
/// seit dem Start der Wiedergabe – dadurch wirken Tempo-Änderungen sofort.
struct SequencerEvent {
    enum Kind { case noteOn, noteOff, click }
    var time: Double
    var kind: Kind
    var pad: Int
    var velocity: Float
}

/// Sample-genauer Step-Sequencer, der vollständig im Audio-Thread läuft.
/// Unabhängig von UI-Timern oder Animationen: Die Engine berechnet für jeden
/// Audio-Block exakt, an welchem Sample ein Schritt beginnt.
final class SequencerClock {
    static let eventCapacity = 1024

    private(set) var state: TransportState = .stopped
    /// Aktuelle Position in Schritten seit Start
    private(set) var position: Double = 0
    var bpm: Double = 120
    /// 50 ... 75 %
    var swing: Double = 50
    var muteMask: UInt16 = 0
    var soloMask: UInt16 = 0
    var metronome = false

    private(set) var patterns: [PatternSnapshot?] = Array(repeating: nil, count: SequencerState.patternSlots)
    private(set) var currentSlot = 0
    private(set) var queuedSlot = -1
    /// Startschritt des aktuell (für die Planung) laufenden Patterns
    private(set) var patternStartStep = 0
    /// Das Pattern vor dem letzten Wechsel: Die Planung läuft bis zu einem Schritt voraus,
    /// hörbar ist das alte Pattern bis `switchStep`.
    private var previousSlot = 0
    private var previousStartStep = 0
    private var switchStep = Int.min

    /// Song-Modus: Kette der Pattern-Slots (nil = aus)
    private(set) var song: SongSnapshot?
    /// Aktueller Eintrag der Kette (−1 = beim nächsten Pattern-Ende mit dem ersten Eintrag beginnen)
    private(set) var songIndex = 0
    private var previousSongIndex = 0

    private var nextStepToQueue = 0
    private let events: UnsafeMutablePointer<SequencerEvent>
    private var eventCount = 0

    init() {
        events = .allocate(capacity: Self.eventCapacity)
    }

    deinit { events.deallocate() }

    // MARK: Steuerung

    /// Ersetzt ein Pattern und gibt das alte (zur Freigabe außerhalb des Audio-Threads) zurück.
    func setPattern(_ snapshot: PatternSnapshot?, slot: Int) -> PatternSnapshot? {
        guard patterns.indices.contains(slot) else { return snapshot }
        let old = patterns[slot]
        patterns[slot] = snapshot
        return old
    }

    /// Setzt oder entfernt die Song-Kette und gibt die alte zur Freigabe zurück.
    func setSong(_ snapshot: SongSnapshot?) -> SongSnapshot? {
        let old = song
        song = snapshot
        if let snapshot {
            queuedSlot = -1
            if state == .stopped {
                songIndex = 0
                currentSlot = snapshot.chain[0]
            } else if old == nil || songIndex >= snapshot.chain.count || snapshot.chain[max(songIndex, 0)] != currentSlot {
                songIndex = snapshot.chain.firstIndex(of: currentSlot) ?? -1
            }
        }
        return old
    }

    func selectPattern(_ slot: Int, immediately: Bool) {
        guard patterns.indices.contains(slot) else { return }
        if state != .playing || immediately {
            markSwitch(at: state == .playing ? nextStepToQueue : Int(position.rounded(.down)))
            currentSlot = slot
            queuedSlot = -1
            if let song, let i = song.chain.firstIndex(of: slot) { songIndex = i }
        } else {
            queuedSlot = slot == currentSlot ? -1 : slot
        }
    }

    private func markSwitch(at step: Int) {
        previousSlot = currentSlot
        previousStartStep = patternStartStep
        previousSongIndex = songIndex
        switchStep = step
        patternStartStep = step
    }

    func play() {
        if state == .stopped {
            position = 0
            nextStepToQueue = 0
            patternStartStep = 0
            switchStep = Int.min
            eventCount = 0
            if let song {
                songIndex = 0
                currentSlot = song.chain[0]
                queuedSlot = -1
            } else if queuedSlot >= 0 {
                currentSlot = queuedSlot; queuedSlot = -1
            }
        }
        state = .playing
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
    }

    func stop() {
        state = .stopped
        position = 0
        nextStepToQueue = 0
        patternStartStep = 0
        switchStep = Int.min
        eventCount = 0
        if let song { songIndex = 0; currentSlot = song.chain[0] }
    }

    /// Das an einer Position hörbare Pattern (Slot, Startschritt, Song-Eintrag).
    @inline(__always)
    func segment(at pos: Double) -> (slot: Int, start: Int, songIndex: Int) {
        if pos < Double(switchStep) { return (previousSlot, previousStartStep, previousSongIndex) }
        return (currentSlot, patternStartStep, songIndex)
    }

    @inline(__always)
    func patternLength(slot: Int) -> Int { max(patterns[slot]?.length ?? 16, 1) }

    /// Schritt im Pattern und Bruchteil an einer Position.
    @inline(__always)
    func location(at pos: Double) -> (slot: Int, step: Int, fraction: Double, length: Int) {
        let seg = segment(at: pos)
        let len = patternLength(slot: seg.slot)
        let rel = pos - Double(seg.start)
        let whole = floor(rel)
        let step = ((Int(whole) % len) + len) % len
        return (seg.slot, step, rel - whole, len)
    }

    // MARK: Zeitberechnung

    func stepsPerSample(sampleRate: Double) -> Double {
        bpm / 60 * 4 / sampleRate
    }

    /// Swing verzögert jeden zweiten 16tel-Schritt. 50 % = gerade, 66,7 % = Triolen-Feel.
    static func swingDelay(step: Int, swing: Double) -> Double {
        guard step % 2 == 1 else { return 0 }
        return (DSP.clamp(swing, 50, 75) - 50) / 50
    }

    var currentPatternLength: Int { patternLength(slot: currentSlot) }

    /// Hörbares Pattern (für Anzeige und Aufnahme)
    var audibleSlot: Int { segment(at: position).slot }
    var audibleSongIndex: Int { segment(at: position).songIndex }

    /// Aktueller Schritt innerhalb des Patterns (für LED-Anzeige).
    var displayStep: Int { location(at: position).step }

    // MARK: Planung

    /// Plant alle Schritte, deren frühestmögliches Ereignis vor `horizon` liegt.
    func schedule(until horizon: Double, isRecording: Bool) {
        while Double(nextStepToQueue) - 0.5 < horizon {
            queueStep(nextStepToQueue)
            nextStepToQueue += 1
        }
    }

    private func queueStep(_ k: Int) {
        var len = max(currentPatternLength, 1)
        if (k - patternStartStep) % len == 0 {
            if let song {
                // Song: am Ende jedes Patterns zum nächsten Ketteneintrag (am Ende wieder von vorn).
                guard k > patternStartStep || songIndex < 0 else { return queueNotes(k, len: len) }
                let next = songIndex + 1 >= song.chain.count ? 0 : songIndex + 1
                markSwitch(at: k)
                songIndex = next
                currentSlot = song.chain[next]
                len = max(currentPatternLength, 1)
            } else if queuedSlot >= 0 {
                markSwitch(at: k)
                currentSlot = queuedSlot
                queuedSlot = -1
                len = max(currentPatternLength, 1)
            }
        }
        queueNotes(k, len: len)
    }

    private func queueNotes(_ k: Int, len: Int) {
        let stepInPattern = ((k - patternStartStep) % len + len) % len
        let swingDelay = Self.swingDelay(step: k, swing: swing)
        if metronome && stepInPattern % 4 == 0 {
            push(SequencerEvent(time: Double(k), kind: .click, pad: stepInPattern == 0 ? 1 : 0, velocity: 1))
        }
        guard let pattern = patterns[currentSlot] else { return }
        let soloActive = soloMask != 0
        for track in 0..<SequencerPattern.trackCount {
            let bit = UInt16(1) << UInt16(track)
            if muteMask & bit != 0 { continue }
            if soloActive && soloMask & bit == 0 { continue }
            let step = pattern.step(track: track, step: stepInPattern)
            guard step.active else { continue }
            let t = Double(k) + swingDelay + step.offset
            push(SequencerEvent(time: t, kind: .noteOn, pad: track, velocity: Float(step.velocity)))
            push(SequencerEvent(time: t + pattern.gates[track], kind: .noteOff, pad: track, velocity: 0))
        }
    }

    private func push(_ event: SequencerEvent) {
        guard eventCount < Self.eventCapacity else { return }
        events[eventCount] = event
        eventCount += 1
    }

    /// Zeitpunkt des nächsten geplanten Ereignisses.
    func nextEventTime() -> Double? {
        guard eventCount > 0 else { return nil }
        var t = events[0].time
        for i in 1..<eventCount where events[i].time < t { t = events[i].time }
        return t
    }

    /// Entnimmt das früheste Ereignis, falls es bis `time` fällig ist.
    func popDueEvent(at time: Double) -> SequencerEvent? {
        guard eventCount > 0 else { return nil }
        var best = -1
        var bestTime = Double.infinity
        for i in 0..<eventCount where events[i].time <= time + 1e-9 && events[i].time < bestTime {
            best = i
            bestTime = events[i].time
        }
        guard best >= 0 else { return nil }
        let e = events[best]
        eventCount -= 1
        events[best] = events[eventCount]
        return e
    }

    /// Entfernt geplante Note-Ons (z. B. beim Stoppen), Note-Offs bleiben erhalten.
    func discardPendingNotes() {
        var i = 0
        while i < eventCount {
            if events[i].kind != .noteOff {
                eventCount -= 1
                events[i] = events[eventCount]
            } else {
                i += 1
            }
        }
    }

    func advance(by steps: Double) {
        if state == .playing { position += steps }
    }
}
