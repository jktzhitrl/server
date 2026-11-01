import Foundation

/// Platzierung live eingespielter Noten im Pattern-Raster.
public enum Quantizer {
    public struct Placement: Equatable {
        public var step: Int
        /// Mikro-Timing relativ zum Raster (-0.5 ..< 0.5 Schritte)
        public var offset: Double
    }

    /// - Parameters:
    ///   - position: Position in Schritten relativ zum Pattern-Anfang (darf außerhalb liegen)
    ///   - length: Pattern-Länge in Schritten
    ///   - mode: Quantisierungsraster
    ///   - swing: Swing in Prozent (wird bei unquantisierter Aufnahme herausgerechnet)
    public static func place(position: Double, length: Int, mode: QuantizeMode, swing: Double = 50) -> Placement {
        let len = max(length, 1)
        let grid = Double(mode.gridSteps ?? 1)
        let rounded = (position / grid).rounded() * grid
        var step = Int(rounded) % len
        if step < 0 { step += len }
        guard mode == .off else { return Placement(step: step, offset: 0) }
        let swingDelay = SequencerClock.swingDelay(step: step, swing: swing)
        var offset = position - rounded - swingDelay
        offset = DSP.clamp(offset, -0.5, 0.499)
        return Placement(step: step, offset: offset)
    }

    /// Quantisiert ein vorhandenes Pattern nachträglich: Mikro-Timing wird entfernt und
    /// Noten werden auf das gewählte Raster verschoben (Kollisionen behalten die lautere Note).
    public static func quantize(_ pattern: Pattern, mode: QuantizeMode) -> Pattern {
        var result = pattern
        let grid = mode.gridSteps ?? 1
        for track in 0..<Pattern.trackCount {
            var newSteps = Array(repeating: SequencerStep(), count: Pattern.maxSteps)
            for s in 0..<pattern.length {
                var step = pattern[track, s]
                guard step.active else { continue }
                let exact = Double(s) + step.offset
                var target = Int((exact / Double(grid)).rounded()) * grid
                target = ((target % pattern.length) + pattern.length) % pattern.length
                step.offset = 0
                if !newSteps[target].active || newSteps[target].velocity < step.velocity {
                    newSteps[target] = step
                }
            }
            for s in pattern.length..<Pattern.maxSteps { newSteps[s] = pattern[track, s] }
            result.steps[track] = newSteps
        }
        return result
    }
}
