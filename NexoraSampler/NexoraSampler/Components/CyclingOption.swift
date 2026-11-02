import NexoraCore

/// Zyklisches Weiterschalten von Auswahlwerten.
protocol CyclingOption: CaseIterable, Equatable where AllCases == [Self] {}

extension CyclingOption {
    var next: Self {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self) else { return self }
        return all[(i + 1) % all.count]
    }
}

extension PlayMode: CyclingOption {}
extension FilterMode: CyclingOption {}
extension MasterModTarget: CyclingOption {}
extension LFOShape: CyclingOption {}
extension PadLFOTarget: CyclingOption {}
extension PitchMode: CyclingOption {}
extension TempoDivision: CyclingOption {}
