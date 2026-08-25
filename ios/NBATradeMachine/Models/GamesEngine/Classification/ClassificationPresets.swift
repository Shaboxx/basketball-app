import Foundation

/// Presets are data (spec §33): a registry card id → the classification game its
/// Start button launches. Computed `static var` for the same Sendable reason as
/// the roster presets.
nonisolated enum ClassificationPresets {

    static let rankId = "rank-players"
    static let tierListId = "tier-list"
    static let startBenchCutId = "start-bench-cut"

    static func definition(for gameId: String) -> ClassificationDefinition? {
        switch gameId {
        case Self.rankId:          return rankPlayers
        case Self.tierListId:      return tierList
        case Self.startBenchCutId: return startBenchCut
        default:                   return nil
        }
    }

    /// Rank 8 of the top-40 players; scored on how close your order is to SwishScore.
    static var rankPlayers: ClassificationDefinition {
        ClassificationDefinition(
            id: Self.rankId, title: "Rank Players",
            config: ClassificationConfig(mode: .totalOrder, labels: [],
                                         subjectCount: 8, candidatePoolSize: 40))
    }

    /// Tier 12 of the top-60 into S/A/B/C/D.
    static var tierList: ClassificationDefinition {
        ClassificationDefinition(
            id: Self.tierListId, title: "Tier List",
            config: ClassificationConfig(mode: .tiers, labels: ["S", "A", "B", "C", "D"],
                                         subjectCount: 12, candidatePoolSize: 60))
    }

    /// Start/Bench/Cut three of the top-30.
    static var startBenchCut: ClassificationDefinition {
        ClassificationDefinition(
            id: Self.startBenchCutId, title: "Start / Bench / Cut",
            config: ClassificationConfig(mode: .uniqueLabels,
                                         labels: ["START", "BENCH", "CUT"],
                                         subjectCount: 3, candidatePoolSize: 30))
    }
}
