import Foundation

/// Maps decoded historical player-season records into the frozen
/// `GameEntityRecord` shape the proven roster engine consumes, and slices the
/// full dataset with a `HistoricalFilter`. All the historical-specific logic
/// (family collapse, eligibility, decade/award prefilter) lives HERE — the
/// engine / evaluator / feasibility / CPU never change.
///
/// `nonisolated` so the 12MB→pool build can run off the main actor.
nonisolated enum HistoricalPoolBuilder {

    /// The three position families in the historical data.
    static let families = ["GUARD", "WING", "BIG"]

    /// Sol Option A — deterministic primary-family collapse. A player may carry
    /// multiple families (e.g. WING+BIG); the engine's slot check compares one
    /// `entity.position`, so we pick a single PRIMARY family by the fixed
    /// priority **BIG > WING > GUARD**. This priority is pinned in a test so a
    /// future refactor can't silently reshuffle pools.
    ///
    /// A record's `positionFamilies` is a non-empty subset of the three families;
    /// an (unexpected) empty/foreign list falls back to "GUARD" so the entity
    /// still lands in a slot rather than being silently dropped.
    static func primaryFamily(_ positionFamilies: [String]) -> String {
        if positionFamilies.contains("BIG") { return "BIG" }
        if positionFamilies.contains("WING") { return "WING" }
        if positionFamilies.contains("GUARD") { return "GUARD" }
        return "GUARD"
    }

    /// Map one record → a `GameEntityRecord`. `id` is the season-unique key.
    /// `position` holds the collapsed PRIMARY family code (GUARD/WING/BIG) — the
    /// family RosterConfigs (`.familyFive`/`.familySixFlex`) list those codes in
    /// their slots' `allowedPositions`. `salary` is nil (no economy on historical
    /// cards). Career/decade/stat fields flow into the additive optional
    /// `GameEntityRecord` fields → new `GameField` cases.
    static func record(_ r: HistoricalSeasonRecord) -> GameEntityRecord {
        GameEntityRecord(
            id: r.id,
            name: r.name,
            team: r.team,
            position: primaryFamily(r.positionFamilies),
            salary: nil,
            rating: r.rating,
            offRating: r.offRating,
            defRating: r.defRating,
            minutes: r.minutes,
            decadeStartYear: r.decadeStartYear,
            seasonStartYear: r.seasonStartYear,
            careerRings: r.career?.rings,
            careerMvp: r.career?.mvp,
            careerFinalsMvp: r.career?.finalsMvp,
            careerAllNba: r.career?.allNba,
            careerAllStar: r.career?.allStar,
            careerAllDefense: r.career?.allDefense,
            draftYear: r.career?.draftYear,
            draftRound: r.career?.draftRound,
            draftPick: r.career?.draftPick,
            pts: r.stats?.pts,
            reb: r.stats?.reb,
            ast: r.stats?.ast,
            netRating: r.stats?.netRating)
    }

    /// Build the prefiltered pool from a dataset + filter. Applies (in order):
    /// PLAYER_SEASON entity type, `eligible == true` (when required), decade,
    /// minRating, and award minimums — then maps each surviving record. The
    /// definition-level `entityConstraints` still run afterward in the engine's
    /// `initialize` (authoritative gate); this only trims the input cheaply.
    static func pool(from dataset: HistoricalDataset,
                     filter: HistoricalFilter) -> [GameEntityRecord] {
        // `Array(...)` materializes the lazy chain into the declared return type.
        Array(
            dataset.players
                .lazy
                .filter { $0.entityType == "PLAYER_SEASON" }
                .filter { !filter.requireEligible || $0.eligible }
                .filter { filter.decadeStartYear == nil || $0.decadeStartYear == filter.decadeStartYear }
                .filter { filter.minRating == nil || $0.rating >= filter.minRating! }
                .filter { passesAwards($0, filter.awardMin) }
                .map(record)
        )
    }

    /// Award-minimum gate: every entry in `awardMin` must be met. An unknown key
    /// (typo) or a record whose career count is absent fails the gate — thin
    /// award pools stay honest rather than silently admitting everyone.
    private static func passesAwards(_ r: HistoricalSeasonRecord,
                                     _ awardMin: [String: Int]?) -> Bool {
        guard let awardMin, !awardMin.isEmpty else { return true }
        for (key, minCount) in awardMin {
            let have: Int?
            switch key {
            case "careerRings":      have = r.career?.rings
            case "careerMvp":        have = r.career?.mvp
            case "careerFinalsMvp":  have = r.career?.finalsMvp
            case "careerAllNba":     have = r.career?.allNba
            case "careerAllStar":    have = r.career?.allStar
            case "careerAllDefense": have = r.career?.allDefense
            default:                 have = nil
            }
            guard let have, have >= minCount else { return false }
        }
        return true
    }
}
