import Foundation

/// Presets are data, not code (spec §33): a registry card id maps to the
/// GameDefinition its Start button launches. Cards with no preset keep showing
/// the placeholder. Later phases append entries; nothing else changes.
nonisolated enum GamePresets {

    /// The one id, shared by the switch AND the definition so a copy-paste typo
    /// can't split them. Must match a `DraftGameRegistry` card id.
    static let bestCurrentPlayersId = "best-current-players"

    static func definition(for gameId: String) -> GameDefinition? {
        switch gameId {
        case Self.bestCurrentPlayersId: return bestCurrentPlayers   // Self. forces expression-pattern match, not a binding
        default: return nil
        }
    }

    /// Snake-draft the best current five (flex slots), one player per NBA team,
    /// judged by summed impact rating. Solo play (1 human, 0 CPUs) degrades
    /// gracefully: a single-seat snake is just build-your-five with a score.
    ///
    /// Computed (not `static let`) so no `Sendable` conformance is required on
    /// `GameDefinition` yet — its `indirect enum GameConstraint` member blocks
    /// automatic Sendable inference, and a fresh value per access sidesteps the
    /// shared-global-state check. When Phase 7 needs these types to cross actor
    /// boundaries, make the value layer `Sendable` and this can revert to `let`.
    static var bestCurrentPlayers: GameDefinition {
        GameDefinition(
            id: Self.bestCurrentPlayersId,
            title: "Best Current Players",
            engineType: .rosterConstruction,
            entityConstraints: [],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .flexFive,
            selection: .snake,
            scoring: .teamRating)
    }
}
