import Foundation

/// Zustand einer Stimme. Die Stimmen liegen in einem vorab angelegten Speicherblock;
/// beim Spielen werden keine Objekte erzeugt.
struct Voice {
    var active = false
    var isPreview = false
    var pad = 0
    var sample: SampleBuffer?

    // Wiedergabeposition (Varispeed) bzw. Lesekopf (Time-Stretch), in Quell-Frames
    var position: Double = 0
    var readHead: Double = 0
    var grain0Start: Double = 0
    var grain0Phase: Double = 0
    var grain1Start: Double = 0
    var grain1Phase: Double = -0.5
    var firstGrain = true

    var envelope = ADSREnvelope()
    var filter = StateVariableFilter()
    var crusher = Bitcrusher()
    var lfo = LFO()
    var gain = SmoothedValue(value: 0)

    var velocityGain: Float = 1
    /// Ausblenden bei Voice-Stealing/Choke (fadeStep > 0 = blendet aus)
    var fadeGain: Float = 1
    var fadeStep: Float = 0
    var age: UInt64 = 0
    var fromSequencer = false
    var released = false
    /// Letzter Ausgangspegel (Hüllkurve × Verstärkung) für Anzeige und "quietest"-Stealing
    var level: Float = 0

    var isFading: Bool { fadeStep > 0 }
}
