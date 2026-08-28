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
    static let budgetBuilderId = "budget-builder"
    /// Phase-8 COMPOSITE_BUILDER — a ROSTER_CONSTRUCTION preset (NOT a new
    /// engine), scored by `ScoringMethod.slotMetric` per category slot.
    static let createAPlayerId = "create-a-player"

    static func definition(for gameId: String) -> GameDefinition? {
        switch gameId {
        case Self.bestCurrentPlayersId: return bestCurrentPlayers   // Self. forces expression-pattern match, not a binding
        case Self.fantasySalaryCapId: return fantasySalaryCap
        case Self.blindDraftId: return blindDraft
        case Self.budgetBuilderId: return budgetBuilder
        case Self.createAPlayerId: return createAPlayer
        default: return nil
        }
    }

    /// COMPOSITE_BUILDER "Create-A-Player" (Phase 8): fill four category slots —
    /// a Scorer, a Defender, a Playmaker, and a Do-It-All — from one player per
    /// NBA team, each slot scored on the metric that fits the category. The Scorer
    /// slot is judged on `offense`, the Defender on `defense`, and the Playmaker /
    /// Do-It-All on `overall`; you're building the best composite by picking the
    /// right specialist for each role. Positionless slots (any position fills any
    /// role), one-per-team (`uniqueBy(.team)`), freePick / non-shared so each
    /// participant builds their own. Scored by `slotMetric`, so the winner is the
    /// higher composite sum. Reuses the existing RosterDraftView (no new View).
    static var createAPlayer: GameDefinition {
        let slots = [
            RosterSlot(id: "SCORER", label: "Scorer", allowedPositions: []),
            RosterSlot(id: "DEFENDER", label: "Defender", allowedPositions: []),
            RosterSlot(id: "PLAYMAKER", label: "Playmaker", allowedPositions: []),
            RosterSlot(id: "DOALL", label: "Do-It-All", allowedPositions: []),
        ]
        return GameDefinition(
            id: Self.createAPlayerId,
            title: "Create-A-Player",
            engineType: .rosterConstruction,
            entityConstraints: [],
            rosterConstraints: [.uniqueBy(.team)],
            roster: RosterConfig(slots: slots),
            selection: .freePick,
            scoring: .slotMetric([
                "SCORER": .offense,
                "DEFENDER": .defense,
                "PLAYMAKER": .overall,
                "DOALL": .overall,
            ]))
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

    /// Draft a flex five under a tier-price cap, one player per NBA team. Better
    /// players cost more tier-points ($1…$6 by impact); the $20 cap forces you to
    /// balance a couple of stars against cheap role players across distinct teams.
    /// FREE_PICK and non-shared (each participant builds their own).
    static var budgetBuilder: GameDefinition {
        GameDefinition(
            id: Self.budgetBuilderId,
            title: "Budget Builder",
            engineType: .rosterConstruction,
            entityConstraints: [],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .flexFive,
            selection: .freePick,
            scoring: .teamRating,
            economy: EconomyConfig(pricingMethod: .tierPrice, startingBudget: 20))
    }
}
