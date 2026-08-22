import Foundation

// MARK: - FantasyWeekStatus

/// The resolution state of one scheduled week.
nonisolated enum FantasyWeekStatus: Equatable {
    /// All scheduled games in this calendar week have concluded and stats are available.
    case completed
    /// This is the current in-progress week (provisional totals).
    case current
    /// This week has not started yet; projections apply.
    case future
}

// MARK: - FantasyMatchupStatus

/// Per-pairing resolution state within a week's outcomes.
nonisolated enum FantasyMatchupStatus: Equatable {
    /// Both sides have at least one resolved player log. Zeros count (team played zero games
    /// but the logs fetch succeeded → the matchup is real, not pending).
    case resolved
    /// At least one side has NO rostered player with a loaded log doc (fetch failure → pending;
    /// never awarded as a loss per spec §3).
    case pending
}

// MARK: - FantasyMatchupOutcome

/// The outcome of one head-to-head pairing for a week (may be pending).
nonisolated struct FantasyMatchupOutcome: Equatable {
    let pairing: FantasyMatchupPairing
    /// Non-nil only when both sides are resolved.
    let result: FantasyMatchupResult?
    let status: FantasyMatchupStatus
}

// MARK: - FantasyWeekOutcome

/// Aggregated outcomes for one schedule week.
nonisolated struct FantasyWeekOutcome: Equatable {
    /// 0-based schedule index (schedule week i ↔ calendar week i+1).
    let weekIndex: Int
    let status: FantasyWeekStatus
    /// One entry per pairing in the week's schedule, including pending pairings.
    let matchupOutcomes: [FantasyMatchupOutcome]

    /// True iff every pairing in this week is fully resolved (no pending side).
    var isDataComplete: Bool {
        matchupOutcomes.allSatisfy { $0.status == .resolved }
    }

    /// Resolved results only (pending pairings excluded).
    var resolvedResults: [FantasyMatchupResult] {
        matchupOutcomes.compactMap { $0.result }
    }
}

// MARK: - FantasyWeeklySeason

/// Pure, nonisolated engine for per-week H2H scoring from actual game logs.
///
/// Converts a schedule of `FantasyScheduleWeek`s + a precomputed productions map
/// into `FantasyWeekOutcome`s, then collapses those into per-team `FantasyRecord`s
/// counting ONLY completed + fully-resolved weeks.
///
/// All logic is `nonisolated` — callers on MainActor pass snapshot values, never
/// store references, so nothing crosses actor isolation.
nonisolated enum FantasyWeeklySeason {

    // MARK: Per-team weekly production

    /// Compute one team's weekly production by aggregating eligible games from the
    /// supplied game-log snapshots.
    ///
    /// - Parameters:
    ///   - rosterSlugs: The player slugs on this team's roster (current or historical,
    ///     depending on how `eligibility` was built).
    ///   - logs: All loaded log docs keyed by canonical slug. A slug present in
    ///     `rosterSlugs` but absent from `logs` is treated as a fetch failure.
    ///   - week: The half-open `[start, end)` interval for this calendar week.
    ///   - eligibility: Per-player eligibility windows; gates which games count for
    ///     this team (local: always-current; hosted: transaction-reconstructed).
    ///   - teamId: The UUID identifying this team in the eligibility map.
    ///   - format: The scoring format (determines points scoring; category formats
    ///     use `categoryTotals`).
    /// - Returns: A `(production, resolved)` tuple where `resolved == false` iff
    ///   NO rostered slug has a loaded log doc (all slugs missing → fetch failure
    ///   → pending). A team whose players all had zero eligible games IS resolved
    ///   (the doc was fetched; they just didn't play) and produces `.zero`.
    static func teamWeekProduction(
        rosterSlugs: [String],
        logs: [String: PlayerGameLogSeason],
        week: DateInterval,
        eligibility: RosterEligibility,
        teamId: UUID,
        format: FantasyFormat
    ) -> (production: FantasyTeamProduction, resolved: Bool) {

        // Canonicalize all slugs up front so every lookup is consistent.
        let canonical = rosterSlugs.map { FantasyValueStore.canonicalSlug($0) }

        // Resolved = at least one rostered slug has a loaded log doc.
        let resolved = canonical.contains { logs[$0] != nil }
        guard resolved else {
            return (.zero, false)
        }

        // Accumulate week totals across all rostered players that have eligible games.
        var pts  = 0, reb  = 0, ast  = 0, stl  = 0, blk  = 0, tov  = 0, fg3m = 0
        var fgm  = 0, fga  = 0, ftm  = 0, fta  = 0
        var weeklyFp = 0.0

        for slug in canonical {
            guard let season = logs[slug] else { continue }
            // Filter to games inside the week that are also within an eligibility window.
            for game in season.games {
                guard !game.missed else { continue }
                guard let gameDate = parseGameDate(game.date) else { continue }
                guard gameDate >= week.start && gameDate < week.end else { continue }
                guard eligibility.isEligible(slug, team: teamId, on: gameDate) else { continue }

                pts  += game.pts  ?? 0
                reb  += game.reb  ?? 0
                ast  += game.ast  ?? 0
                stl  += game.stl  ?? 0
                blk  += game.blk  ?? 0
                tov  += game.tov  ?? 0
                fg3m += game.fg3m ?? 0
                fgm  += game.fgm  ?? 0
                fga  += game.fga  ?? 0
                ftm  += game.ftm  ?? 0
                fta  += game.fta  ?? 0
                weeklyFp += FantasyPointsWeights.points(for: game, format: format)
            }
        }

        // Apply sign-flip and volume-weighting rules per spec §Engine + ActualsStatSource.
        let totals = FantasyValue.CategoryZ(
            pts:   Double(pts),
            reb:   Double(reb),
            ast:   Double(ast),
            stl:   Double(stl),
            blk:   Double(blk),
            to:    -Double(tov),              // INVERT: higher is better
            fg3m:  Double(fg3m),
            fgPct: fga > 0 ? Double(fgm) / Double(fga) : 0,   // volume-weighted
            ftPct: fta > 0 ? Double(ftm) / Double(fta) : 0    // volume-weighted
        )

        // For points formats: weekly fp is the sum of per-game fantasy points earned
        // (FantasyPointsWeights returns 0 for non-points formats, so weeklyFp == 0 there).
        let production = FantasyTeamProduction(categoryTotals: totals, pointsPerGame: weeklyFp)
        return (production, true)
    }

    // MARK: Week outcomes

    /// Classify every week in the schedule and score all resolved matchups.
    ///
    /// - Parameters:
    ///   - schedule: The league's full schedule (0-based; week i ↔ calendar week i+1).
    ///   - calendar: The fantasy calendar for week-date lookups.
    ///   - now: The current moment (determines current / completed / future status).
    ///   - productionsByWeek: Precomputed `[weekIndex: [teamId: (production, resolved)]]`.
    ///     The production tuple is from `teamWeekProduction`.
    ///   - format: The scoring format passed through to `FantasyMatchupScoring.score`.
    ///   - customCategories: Optional category mask (forwarded to scoring).
    /// - Returns: One `FantasyWeekOutcome` per schedule week, in order.
    static func weekOutcomes(
        schedule: [FantasyScheduleWeek],
        calendar: FantasyCalendar,
        now: Date,
        productionsByWeek: [Int: [UUID: (FantasyTeamProduction, Bool)]],
        format: FantasyFormat,
        customCategories: [FantasyLeagueCategory]? = nil
    ) -> [FantasyWeekOutcome] {

        let currentCalendarWeek = calendar.weekIndex(on: now)   // 1-based or nil

        return schedule.map { week in
            // Schedule index is 0-based; calendar week is 1-based (spec §2).
            let calendarWeek = week.index + 1

            // Determine week status.
            let status: FantasyWeekStatus
            if let cw = currentCalendarWeek {
                if calendarWeek < cw {
                    status = .completed
                } else if calendarWeek == cw {
                    status = .current
                } else {
                    status = .future
                }
            } else {
                // Calendar not in season — all weeks are either past or future.
                // Use date comparison: if week's end <= now → completed, else → future.
                if let range = calendar.weekDateRange(week: calendarWeek), range.end <= now {
                    status = .completed
                } else {
                    status = .future
                }
            }

            // Score each pairing.
            let weekProds = productionsByWeek[week.index] ?? [:]
            let matchupOutcomes: [FantasyMatchupOutcome] = week.pairings.map { pairing in
                let homePair = weekProds[pairing.home]
                let awayPair = weekProds[pairing.away]

                // Both sides must be resolved (spec §3 / §Engine).
                // resolved=false means NO log doc was loaded → fetch failure → pending.
                let homeResolved = homePair?.1 ?? false
                let awayResolved = awayPair?.1 ?? false

                guard homeResolved && awayResolved else {
                    return FantasyMatchupOutcome(pairing: pairing, result: nil, status: .pending)
                }

                // Build a productions map for the scorer.
                let prods: [UUID: FantasyTeamProduction] = [
                    pairing.home: homePair?.0 ?? .zero,
                    pairing.away: awayPair?.0 ?? .zero,
                ]

                let result = FantasyMatchupScoring.score(
                    home: pairing.home, away: pairing.away,
                    productions: prods,
                    format: format,
                    customCategories: customCategories)

                return FantasyMatchupOutcome(pairing: pairing, result: result, status: .resolved)
            }

            return FantasyWeekOutcome(
                weekIndex: week.index,
                status: status,
                matchupOutcomes: matchupOutcomes)
        }
    }

    // MARK: Records

    /// Accumulate per-team `FantasyRecord`s from week outcomes.
    ///
    /// ONLY counts matchups from weeks that are:
    ///   1. `.completed` (not current or future), AND
    ///   2. fully data-complete (every pairing in the week is resolved — no pending).
    ///
    /// Within such weeks, pending individual pairings (included in `matchupOutcomes`
    /// but with `status == .pending`) are still excluded because `.isDataComplete`
    /// requires all pairings to be resolved. Zero-game but resolved matchups count.
    ///
    /// - Returns: A map of `teamId → FantasyRecord` covering all eligible weeks.
    static func records(from outcomes: [FantasyWeekOutcome]) -> [UUID: FantasyRecord] {
        var out: [UUID: FantasyRecord] = [:]

        for week in outcomes {
            // Only completed, fully-resolved weeks accumulate.
            guard week.status == .completed && week.isDataComplete else { continue }

            for mo in week.matchupOutcomes {
                guard mo.status == .resolved, let r = mo.result else { continue }

                var h = out[r.home] ?? .init()
                var a = out[r.away] ?? .init()

                h.pointsFor += r.homePoints
                a.pointsFor += r.awayPoints

                if !r.isPoints {
                    h.categoryWins   += r.homeCategoryWins
                    h.categoryLosses += r.awayCategoryWins
                    a.categoryWins   += r.awayCategoryWins
                    a.categoryLosses += r.homeCategoryWins
                    h.categoryTies   += r.categoryTies
                    a.categoryTies   += r.categoryTies
                }

                switch r.outcome {
                case .home: h.wins  += 1; a.losses += 1
                case .away: a.wins  += 1; h.losses += 1
                case .tie:  h.ties  += 1; a.ties   += 1
                }

                out[r.home] = h
                out[r.away] = a
            }
        }

        return out
    }

    // MARK: Completed-week count

    /// Number of calendar weeks that have fully concluded before `now`.
    /// Returns 0 when the calendar is unconfigured or `now` is before the season.
    static func completedWeeks(calendar: FantasyCalendar, now: Date) -> Int {
        guard let start = calendar.seasonStart, let end = calendar.seasonEnd,
              let total = calendar.totalWeeks else { return 0 }
        // All weeks are done when we're at/past season end.
        if now >= end { return total }
        // Current 1-based week: weeks before it are completed.
        guard let currentWeek = calendar.weekIndex(on: now) else { return 0 }
        return max(0, currentWeek - 1)
    }

    // MARK: Private helpers

    /// Parse a "yyyy-MM-dd" game-date string as start-of-day in the league timezone.
    /// Returns nil on a bad format (silently skips the game — same as FantasyWeekAggregator).
    private static func parseGameDate(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = FantasyCalendar.zone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: s)
    }
}
