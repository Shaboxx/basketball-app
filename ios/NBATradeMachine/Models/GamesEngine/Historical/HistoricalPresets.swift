import Foundation

/// Presets are data (spec §33): a registry card id → the historical
/// `GameDefinition` its Start button launches. These are the Phase-4.5 sibling
/// of `GamePresets` — every definition sets `poolSource = .historical(filter)`,
/// a family RosterConfig, and (where relevant) decade/award `entityConstraints`.
/// No engine edits; `GameLauncher.resolve` probes this after `GamePresets`.
///
/// The `filter` on a definition's pool source is only a CHEAP prefilter; the
/// `entityConstraints` below are the authoritative gate the engine applies. They
/// are kept in sync (e.g. a decade card filters AND constrains on the decade) so
/// the pool the view builds and the pool the engine keeps are identical.
///
/// Computed `static var` (not `let`) for the same Sendable reason as
/// `GamePresets`: `GameDefinition`'s `indirect enum GameConstraint` member blocks
/// automatic Sendable inference.
nonisolated enum HistoricalPresets {

    // Ids — each MUST match a `DraftGameRegistry` card id.
    static let best6Man2020sId = "best-6man-2020s"       // flipped card
    static let best90sId = "best-1990s-draft"            // flipped + relabeled card
    static let allDecade2000sId = "all-decade-2000s"
    static let allDecade2010sId = "all-decade-2010s"
    static let allTimeFiveId = "all-time-best-five"
    static let ringsOnlyId = "champions-draft"
    static let mvpClubId = "mvp-club"
    static let allNbaId = "all-nba-draft"

    /// All historical ids (for tests / registry cross-checks).
    static let allIds: [String] = [
        best6Man2020sId, best90sId, allDecade2000sId, allDecade2010sId,
        allTimeFiveId, ringsOnlyId, mvpClubId, allNbaId,
    ]

    static func definition(for gameId: String) -> GameDefinition? {
        switch gameId {
        case Self.best6Man2020sId:  return best6Man2020s
        case Self.best90sId:        return best90sDraft
        case Self.allDecade2000sId: return allDecade2000s
        case Self.allDecade2010sId: return allDecade2010s
        case Self.allTimeFiveId:    return allTimeBestFive
        case Self.ringsOnlyId:      return championsDraft
        case Self.mvpClubId:        return mvpClub
        case Self.allNbaId:         return allNbaDraft
        default:                    return nil
        }
    }

    // MARK: - Decade constraint helper

    /// The decade entity constraint (`decadeStartYear == year`), matching the
    /// pool-source filter so the engine keeps exactly the prefiltered pool.
    private static func decadeConstraint(_ year: Int) -> GameConstraint {
        .field(FieldConstraint(field: .decadeStartYear, op: .equal, value: .number(Double(year))))
    }

    private static func awardConstraint(_ field: GameField, atLeast n: Int) -> GameConstraint {
        .field(FieldConstraint(field: field, op: .greaterOrEqual, value: .number(Double(n))))
    }

    // MARK: - Decade cards

    /// 2020s six-man rotation: familySixFlex (G/G/W/W/B + FLEX), snake, judged by
    /// summed rating. Pool = eligible 2020-decade seasons.
    static var best6Man2020s: GameDefinition {
        GameDefinition(
            id: Self.best6Man2020sId,
            title: "Best 6-Man 2020s",
            engineType: .rosterConstruction,
            entityConstraints: [decadeConstraint(2020)],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .familySixFlex,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(decadeStartYear: 2020)))
    }

    /// Best 90s Draft (1996+) — relabeled per Sol (data floor is 1996-97). Pool =
    /// eligible 1990-decade seasons (1064). familyFive, snake, teamRating.
    static var best90sDraft: GameDefinition {
        GameDefinition(
            id: Self.best90sId,
            title: "Best 90s Draft (1996+)",
            engineType: .rosterConstruction,
            entityConstraints: [decadeConstraint(1990)],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(decadeStartYear: 1990)))
    }

    /// All-Decade 2000s — eligible 2000-decade seasons (2811). familyFive.
    static var allDecade2000s: GameDefinition {
        GameDefinition(
            id: Self.allDecade2000sId,
            title: "All-Decade 2000s",
            engineType: .rosterConstruction,
            entityConstraints: [decadeConstraint(2000)],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(decadeStartYear: 2000)))
    }

    /// All-Decade 2010s — eligible 2010-decade seasons (3112). familyFive.
    static var allDecade2010s: GameDefinition {
        GameDefinition(
            id: Self.allDecade2010sId,
            title: "All-Decade 2010s",
            engineType: .rosterConstruction,
            entityConstraints: [decadeConstraint(2010)],
            rosterConstraints: [.uniqueBy(.team)],
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(decadeStartYear: 2010)))
    }

    // MARK: - All-time / award cards

    /// All-Time Best Five — the full eligible pool (9004 player-seasons), any
    /// decade, familyFive, no roster constraint (pick the five best you can).
    /// DOCUMENTED LIMITATION: entities are player-SEASONS, so the same player
    /// COULD be drafted twice (two different seasons) on one roster. Preventing
    /// that would need a player-id GameField + a uniqueBy on it (out of scope —
    /// the engine/field set stays as-is per Sol).
    static var allTimeBestFive: GameDefinition {
        GameDefinition(
            id: Self.allTimeFiveId,
            title: "All-Time Best Five",
            engineType: .rosterConstruction,
            entityConstraints: [],
            rosterConstraints: [],
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(.allEligible))
    }

    /// Champions Draft — only player-seasons whose player won >= 1 ring (2288
    /// eligible). familyFive.
    static var championsDraft: GameDefinition {
        GameDefinition(
            id: Self.ringsOnlyId,
            title: "Champions Draft",
            engineType: .rosterConstruction,
            entityConstraints: [awardConstraint(.careerRings, atLeast: 1)],
            // No uniqueBy(.team): award pools are the point, not team diversity —
            // and dropping it keeps the thinner award cards comfortably feasible
            // (a player-season can repeat a franchise across seasons).
            rosterConstraints: [],
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(awardMin: ["careerRings": 1])))
    }

    /// MVP Club — only MVP-winning players (>=1). A deliberately thin pool (281
    /// eligible), still far above the 5 slots. familyFive.
    static var mvpClub: GameDefinition {
        GameDefinition(
            id: Self.mvpClubId,
            title: "MVP Club",
            engineType: .rosterConstruction,
            entityConstraints: [awardConstraint(.careerMvp, atLeast: 1)],
            rosterConstraints: [],   // thin pool — no uniqueBy (see championsDraft)
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(awardMin: ["careerMvp": 1])))
    }

    /// All-NBA Draft — All-NBA players (>=1) (1496 eligible). familyFive.
    static var allNbaDraft: GameDefinition {
        GameDefinition(
            id: Self.allNbaId,
            title: "All-NBA Draft",
            engineType: .rosterConstruction,
            entityConstraints: [awardConstraint(.careerAllNba, atLeast: 1)],
            rosterConstraints: [],   // award pool — no uniqueBy (see championsDraft)
            roster: .familyFive,
            selection: .snake,
            scoring: .teamRating,
            poolSource: .historical(HistoricalFilter(awardMin: ["careerAllNba": 1])))
    }
}
