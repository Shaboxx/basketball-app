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
            netRating: r.stats?.netRating,
            // Phase-5 content fields — the richer stat + label surface GUESS/QUIZ/
            // SURVIVOR draw clues, superlatives, and predicates from.
            seasonLabel: r.seasonLabel,
            age: r.age,
            stl: r.stats?.stl,
            blk: r.stats?.blk,
            tov: r.stats?.tov,
            fgPct: r.stats?.fgPct,
            threePct: r.stats?.threePct,
            ftPct: r.stats?.ftPct,
            tsPct: r.stats?.tsPct,
            usgPct: r.stats?.usgPct,
            pie: r.stats?.pie)
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

    // MARK: - Phase-6 DISTINCT-player collapse (GRID / CONNECTION answer space)

    /// Collapse the season-level dataset into DISTINCT players — one
    /// `HistoricalPlayerEntity` per `nbaPlayerId`, keeping only `eligible == true`
    /// season rows and UNIONING their franchises/decades/families while taking the
    /// MAX of each career-accolade count and the best (max) rating. This is the
    /// shared answer-space for GRID (set-membership axes) and CONNECTION (name
    /// resolution). Pure — feedable a `HistoricalDataset` decoded off any Data blob.
    ///
    /// Determinism: entities are returned sorted by `id` (numeric-then-lexical is
    /// unnecessary — the id is the stable key), so the same dataset always yields
    /// the same ordering for reproducible seeded draws. The per-player display
    /// `name`/`appSlug` are taken from the player's MOST-RECENT eligible season
    /// (highest `seasonStartYear`), so the answer index shows a current name.
    static func loadDistinctPlayers(from dataset: HistoricalDataset) -> [HistoricalPlayerEntity] {
        // Group eligible PLAYER_SEASON rows by nbaPlayerId.
        var grouped: [Int: [HistoricalSeasonRecord]] = [:]
        for r in dataset.players where r.entityType == "PLAYER_SEASON" && r.eligible {
            grouped[r.nbaPlayerId, default: []].append(r)
        }

        var entities: [HistoricalPlayerEntity] = []
        entities.reserveCapacity(grouped.count)
        for (playerId, rows) in grouped {
            // Most-recent eligible season → display name / slug (tie: last in a
            // deterministic id-sorted order so the pick is reproducible).
            let latest = rows.max { a, b in
                if a.seasonStartYear != b.seasonStartYear { return a.seasonStartYear < b.seasonStartYear }
                return a.id < b.id
            }!

            var franchiseSet = Set<String>()
            var decadeSet = Set<Int>()
            var familySet = Set<String>()
            var rings = 0, mvp = 0, allNba = 0, allStar = 0, allDefense = 0
            var bestRating = -Double.greatestFiniteMagnitude
            for r in rows {
                franchiseSet.insert(r.team)
                decadeSet.insert(r.decadeStartYear)
                // Only admit the three canonical families (guards a stray token).
                for f in r.positionFamilies where families.contains(f) { familySet.insert(f) }
                rings      = max(rings, r.career?.rings ?? 0)
                mvp        = max(mvp, r.career?.mvp ?? 0)
                allNba     = max(allNba, r.career?.allNba ?? 0)
                allStar    = max(allStar, r.career?.allStar ?? 0)
                allDefense = max(allDefense, r.career?.allDefense ?? 0)
                bestRating = max(bestRating, r.rating)
            }

            entities.append(HistoricalPlayerEntity(
                id: String(playerId),
                name: latest.name,
                appSlug: latest.appSlug,
                franchises: franchiseSet,
                decades: decadeSet,
                families: familySet,
                careerRings: rings,
                careerMvp: mvp,
                careerAllNba: allNba,
                careerAllStar: allStar,
                careerAllDefense: allDefense,
                bestRating: bestRating == -Double.greatestFiniteMagnitude ? 0 : bestRating))
        }
        return entities.sorted { $0.id < $1.id }
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
