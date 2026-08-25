import Foundation

/// Higher/Lower presets (spec §19). Computed `static var` (Sendable).
nonisolated enum ComparePresets {

    static let biggerContractId = "bigger-contract"
    static let higherRatedId = "higher-rated"

    static func definition(for gameId: String) -> CompareDefinition? {
        switch gameId {
        case Self.biggerContractId: return biggerContract
        case Self.higherRatedId:    return higherRated
        default:                    return nil
        }
    }

    /// Guess who's paid more — endless streak.
    static var biggerContract: CompareDefinition {
        CompareDefinition(id: Self.biggerContractId, title: "Bigger Contract",
                          config: CompareConfig(metric: .salary, direction: .higher))
    }

    /// Guess who the model rates higher.
    static var higherRated: CompareDefinition {
        CompareDefinition(id: Self.higherRatedId, title: "Higher Rated",
                          config: CompareConfig(metric: .overall, direction: .higher))
    }
}
