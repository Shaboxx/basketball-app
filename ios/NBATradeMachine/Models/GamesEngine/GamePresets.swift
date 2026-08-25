import Foundation

/// Presets are data, not code (spec §33): a registry card id maps to the
/// GameDefinition its Start button launches. Cards with no preset keep showing
/// the placeholder. Later phases append entries; nothing else changes.
nonisolated enum GamePresets {

    /// The one id, shared by the switch AND the definition so a copy-paste typo
    /// can't split them. Must match a `DraftGameRegistry` card id.
    static let bestCurrentPlayersId = "best-current-players"
    static let fantasySalaryCapId = "fantasy-salary-cap"
    static let blindDraftId = "blind-draft"

    static func definition(for gameId: String) -> GameDefinition? {
        switch gameId {
        case Self.bestCurrentPlayersId: return bestCurrentPlayers   // Self. forces expression-pattern match, not a binding
        case Self.fantasySalaryCapId: return fantasySalaryCap
        case Self.blindDraftId: return blindDraft
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

    /// Build the best flex-five you can afford under a real-salary cap. FREE_PICK
    /// and non-shared, so each participant builds their own team from the full
    /// pool; scored by summed impact rating. The `salary >= 1` entity constraint
    /// filters out nil/$0-salary players (who would otherwise price as free).
    /// Computed (not `static let`) for the same Sendable reason as
    /// `bestCurrentPlayers`.
    static var fantasySalaryCap: GameDefinition {
        GameDefinition(
            id: Self.fantasySalaryCapId,
            title: "Fantasy Salary Cap",
            engineType: .rosterConstruction,
            entityConstraints: [
                .field(FieldConstraint(field: .salary, op: .greaterOrEqual,
                                       value: .number(1)))
            ],
            rosterConstraints: [],
            roster: .flexFive,
            selection: .freePick,
            scoring: .teamRating,
            economy: EconomyConfig(pricingMethod: .databaseValue,
                                   startingBudget: 120_000_000))
    }

    /// One masked random player per turn (`randomOffer(1)`); identity + rating
    /// hidden until you commit them to a slot; two rerolls if you don't like the
    /// silhouette. Scored by summed rating so the reveal is the payoff.
    static var blindDraft: GameDefinition {
        GameDefinition(
            id: Self.blindDraftId,
            title: "Blind Draft",
            engineType: .rosterConstruction,
            entityConstraints: [],
            rosterConstraints: [],
            roster: .flexFive,
            selection: .randomOffer(1),
            scoring: .teamRating,
            reveal: RevealConfig(mode: .afterSlotAssignment, hidden: [.identity, .rating]),
            specialActions: SpecialActionsConfig(rerolls: 2))
    }
}
