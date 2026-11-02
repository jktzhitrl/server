import Foundation
#if canImport(os)
import os
#endif
#if canImport(Glibc)
import Glibc
#endif

/// Mutex mit `tryLock`. Der Audio-Thread verwendet ausschließlich `tryLock`
/// und blockiert dadurch nie; Producer (UI-/MIDI-Thread) halten den Lock nur
/// für eine einzelne Zuweisung.
final class TryLock {
    #if canImport(os)
    private let lockPointer: UnsafeMutablePointer<os_unfair_lock>
    init() {
        lockPointer = .allocate(capacity: 1)
        lockPointer.initialize(to: os_unfair_lock())
    }
    deinit { lockPointer.deallocate() }
    @inline(__always) func lock() { os_unfair_lock_lock(lockPointer) }
    @inline(__always) func unlock() { os_unfair_lock_unlock(lockPointer) }
    @inline(__always) func tryLock() -> Bool { os_unfair_lock_trylock(lockPointer) }
    #else
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }
    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }
    @inline(__always) func lock() { pthread_mutex_lock(mutex) }
    @inline(__always) func unlock() { pthread_mutex_unlock(mutex) }
    @inline(__always) func tryLock() -> Bool { pthread_mutex_trylock(mutex) == 0 }
    #endif
}

/// Ringpuffer fester Größe. Speicher wird einmalig angelegt; im Betrieb finden
/// keine Allokationen statt.
final class RealtimeRing<Element> {
    private let storage: UnsafeMutablePointer<Element?>
    private let capacity: Int
    private var head = 0
    private var tail = 0
    private var count = 0
    private let lock = TryLock()

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: nil, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Blockierendes Einfügen (nur außerhalb des Audio-Threads verwenden).
    @discardableResult
    func push(_ element: Element) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return unsafePush(element)
    }

    /// Nicht-blockierendes Einfügen (für den Audio-Thread).
    @discardableResult
    func tryPush(_ element: Element) -> Bool {
        guard lock.tryLock() else { return false }
        defer { lock.unlock() }
        return unsafePush(element)
    }

    @inline(__always)
    private func unsafePush(_ element: Element) -> Bool {
        guard count < capacity else { return false }
        storage[tail] = element
        tail = (tail + 1) % capacity
        count += 1
        return true
    }

    /// Entnimmt alle Elemente, ohne zu blockieren. Gibt `false` zurück, wenn der Lock
    /// gerade belegt war (dann im nächsten Zyklus erneut versuchen).
    @inline(__always)
    func tryDrain(_ body: (Element) -> Void) -> Bool {
        guard lock.tryLock() else { return false }
        defer { lock.unlock() }
        while count > 0 {
            let element = storage[head]
            storage[head] = nil
            head = (head + 1) % capacity
            count -= 1
            if let element { body(element) }
        }
        return true
    }

    /// Blockierendes Entnehmen (außerhalb des Audio-Threads).
    func drain(_ body: (Element) -> Void) {
        lock.lock()
        var items: [Element] = []
        while count > 0 {
            if let e = storage[head] { items.append(e) }
            storage[head] = nil
            head = (head + 1) % capacity
            count -= 1
        }
        lock.unlock()
        items.forEach(body)
    }
}

/// Gemeinsam genutzter Statusspeicher zwischen Audio-Thread (schreibt) und UI (liest).
/// Es werden ausschließlich ausgerichtete 32-Bit-Werte geschrieben und gelesen; auf
/// arm64 und x86_64 sind solche Zugriffe atomar. Die UI liest mit 30–60 Hz.
public final class EngineStatus: @unchecked Sendable {
    enum Slot: Int {
        case currentStep = 0, transport, activeVoices, peakLeft, peakRight
        case currentPattern, queuedPattern, positionSteps, gainReduction, load, recording, songIndex
    }
    static let padLevelBase = 16
    static let padTriggerBase = 40
    static let size = 64

    let storage: UnsafeMutablePointer<Float>

    init() {
        storage = .allocate(capacity: Self.size)
        storage.initialize(repeating: 0, count: Self.size)
        storage[Slot.queuedPattern.rawValue] = -1
        storage[Slot.songIndex.rawValue] = -1
    }

    deinit { storage.deallocate() }

    @inline(__always) func write(_ slot: Slot, _ value: Float) { storage[slot.rawValue] = value }
    @inline(__always) func read(_ slot: Slot) -> Float { storage[slot.rawValue] }

    public var currentStep: Int { Int(read(.currentStep)) }
    public var transport: TransportState { TransportState(rawValue: Int(read(.transport))) ?? .stopped }
    public var activeVoices: Int { Int(read(.activeVoices)) }
    public var peakLeft: Float { read(.peakLeft) }
    public var peakRight: Float { read(.peakRight) }
    public var currentPattern: Int { Int(read(.currentPattern)) }
    /// -1 = kein Wechsel vorgemerkt
    public var queuedPattern: Int { Int(read(.queuedPattern)) }
    /// Eintrag der Song-Kette, der gerade läuft (−1 = Song-Modus aus)
    public var songIndex: Int { Int(read(.songIndex)) }
    public var positionInSteps: Double { Double(read(.positionSteps)) }
    public var gainReductionDb: Float { read(.gainReduction) }
    /// Anteil der verfügbaren Renderzeit (0 ... 1)
    public var load: Float { read(.load) }

    /// Aktueller Hüllkurvenpegel eines Pads (0 ... ~1)
    public func padLevel(_ pad: Int) -> Float { storage[Self.padLevelBase + pad] }
    /// Zähler, der bei jedem Anschlag eines Pads erhöht wird
    public func padTriggerCount(_ pad: Int) -> Int { Int(storage[Self.padTriggerBase + pad]) }
}

public enum TransportState: Int, Sendable {
    case stopped = 0, playing = 1, paused = 2
}
