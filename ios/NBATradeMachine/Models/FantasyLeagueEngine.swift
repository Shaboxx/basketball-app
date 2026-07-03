import Foundation

/// The 9 scoring categories, with the label set that matches `FantasyCategoryOrder`
/// ("PTS","REB","AST","STL","BLK","TO","3PM","FG%","FT%") and an accessor into a
/// summed `CategoryZ`. Turnovers (`to`) are already sign-flipped server-side
/// (positive z = good), so EVERY category is "higher z is better" — no special-casing.
nonisolated enum FantasyLeagueCategory: String, Codable, CaseIterable {
    case pts, reb, ast, stl, blk, to, fg3m, fgPct, ftPct

    var label: String {
        switch self {
        case .pts: return "PTS";  case .reb: return "REB";  case .ast: return "AST"
        case .stl: return "STL";  case .blk: return "BLK";  case .to:  return "TO"
        case .fg3m: return "3PM"; case .fgPct: return "FG%"; case .ftPct: return "FT%"
        }
    }

    func z(in c: FantasyValue.CategoryZ) -> Double {
        switch self {
        case .pts: return c.pts;  case .reb: return c.reb;  case .ast: return c.ast
        case .stl: return c.stl;  case .blk: return c.blk;  case .to:  return c.to
        case .fg3m: return c.fg3m; case .fgPct: return c.fgPct; case .ftPct: return c.ftPct
        }
    }

    /// Categories that participate for a given format. 8-cat drops turnovers; 9-cat and
    /// roto use all nine. (Points formats never call this — they score on `pointsPerGame`.)
    static func categories(for format: FantasyFormat) -> [FantasyLeagueCategory] {
        switch format {
        case .eightCat: return allCases.filter { $0 != .to }
        default:        return allCases
        }
    }

    /// The active category set: a league's CUSTOM mask when present (canonical
    /// order, so the UI reads consistently), else the format's preset set.
    static func active(format: FantasyFormat,
                       custom: [FantasyLeagueCategory]?) -> [FantasyLeagueCategory] {
        if let custom, !custom.isEmpty { return allCases.filter(custom.contains) }
        return categories(for: format)
    }
}

/// League-wide per-category spread, for LIVE-mode presentation. Projected productions
/// are z-sums, so a matchup diff already lives on the bar's ±3σ window; live productions
/// are RAW per-game rates (points ~ 8–15, FG% ~ 0.01) whose diffs must be normalized by
/// the league's spread in that category before they can share the same bar. Presentation
/// scale ONLY — the engine itself stays scale-invariant and never uses this.
nonisolated enum FantasyCategoryScale {

    /// Population SD of one category's team totals across the league.
    /// Degenerate spreads (fewer than 2 teams, all equal, non-finite) → 0.
    static func sd(productions: [FantasyTeamProduction],
                   category: FantasyLeagueCategory) -> Double {
        let vals = productions.map { category.z(in: $0.categoryTotals) }
        guard vals.count >= 2 else { return 0 }
        let mean = vals.reduce(0, +) / Double(vals.count)
        var varSum = 0.0
        for v in vals { varSum += (v - mean) * (v - mean) }
        let sd = (varSum / Double(vals.count)).squareRoot()
        return sd.isFinite ? sd : 0
    }

    /// diff / sd with a zero-spread guard — the live-mode bar value.
    static func normalizedDiff(_ diff: Double, sd: Double) -> Double {
        sd > 0 ? diff / sd : 0
    }
}

/// One scheduled head-to-head pairing.
nonisolated struct FantasyMatchupPairing: Equatable, Hashable, Identifiable {
    let home: UUID
    let away: UUID
    var id: String { "\(home.uuidString)+\(away.uuidString)" }
}

/// One week of the round-robin. `bye` is the team resting this week (odd member counts).
nonisolated struct FantasyScheduleWeek: Equatable, Identifiable {
    let index: Int                          // 0-based
    let pairings: [FantasyMatchupPairing]
    let bye: UUID?
    var id: Int { index }
}

/// Deterministic round-robin generation (circle method). Given the SAME ordered
/// `teamIds`, the output is identical — so we NEVER store it: it regenerates whenever
/// membership changes and can't drift. Even counts → `n-1` weeks, `n/2` matchups each.
/// Odd counts → pad with a sentinel bye so exactly one team rests per week.
nonisolated enum FantasyLeagueSchedule {

    static func roundRobin(_ teamIds: [UUID]) -> [FantasyScheduleWeek] {
        guard teamIds.count >= 2 else { return [] }     // no matchups below 2 teams

        var arr: [UUID?] = teamIds
        if arr.count % 2 != 0 { arr.append(nil) }        // bye marker
        let n = arr.count
        let half = n / 2
        let rounds = n - 1

        var weeks: [FantasyScheduleWeek] = []
        for r in 0..<rounds {
            var pairings: [FantasyMatchupPairing] = []
            var bye: UUID?
            for i in 0..<half {
                let a = arr[i]
                let b = arr[n - 1 - i]
                if let a, let b {
                    pairings.append(FantasyMatchupPairing(home: a, away: b))
                } else {
                    bye = a ?? b                          // the non-nil side sits out
                }
            }
            weeks.append(FantasyScheduleWeek(index: r, pairings: pairings, bye: bye))

            // Rotate: keep arr[0] fixed, move the last of the rest to the front.
            let fixed = arr[0]
            var rest = Array(arr[1...])
            if let last = rest.popLast() { rest.insert(last, at: 0) }
            arr = [fixed] + rest
        }
        return weeks
    }

    /// The league's regular-season schedule for display + standings — the base
    /// round-robin CYCLED or TRUNCATED to a commissioner-set length. Passing nil
    /// (or a count equal to the natural length) yields the plain single round-robin;
    /// a larger count repeats the base rounds (each successive cycle flips home/away
    /// so a pair alternates sides), a smaller count keeps only the first weeks. The
    /// output is 0-indexed 0..<count and still a pure function of `teamIds` + the
    /// count, so it is never stored and can't drift. Byes carry through each cycle.
    static func resolved(teamIds: [UUID], regularSeasonWeeks weeks: Int?) -> [FantasyScheduleWeek] {
        let base = roundRobin(teamIds)
        guard let weeks, weeks >= 1, !base.isEmpty, weeks != base.count else { return base }

        var out: [FantasyScheduleWeek] = []
        out.reserveCapacity(weeks)
        for i in 0..<weeks {
            let src = base[i % base.count]
            let flip = (i / base.count) % 2 == 1        // alternate home/away each full cycle
            let pairings = src.pairings.map { p in
                flip ? FantasyMatchupPairing(home: p.away, away: p.home) : p
            }
            out.append(FantasyScheduleWeek(index: i, pairings: pairings, bye: src.bye))
        }
        return out
    }
}

/// One category line in a head-to-head matchup.
nonisolated struct FantasyCategoryLine: Equatable {
    enum Outcome: Equatable { case home, away, tie }
    let category: FantasyLeagueCategory
    let homeZ: Double
    let awayZ: Double
    var outcome: Outcome { homeZ > awayZ ? .home : (awayZ > homeZ ? .away : .tie) }
}

/// The result of scoring ONE matchup. Category formats fill `lines` + the category
/// tallies; points formats fill `homePoints`/`awayPoints`. `outcome` is the overall
/// winner (more categories won, or higher points).
nonisolated struct FantasyMatchupResult: Equatable {
    enum Outcome: Equatable { case home, away, tie }
    let home: UUID
    let away: UUID
    let isPoints: Bool
    let lines: [FantasyCategoryLine]        // empty for points formats
    let homeCategoryWins: Int
    let awayCategoryWins: Int
    let categoryTies: Int
    let homePoints: Double                  // 0 for category formats
    let awayPoints: Double

    var outcome: Outcome {
        if isPoints {
            return homePoints > awayPoints ? .home : (awayPoints > homePoints ? .away : .tie)
        }
        return homeCategoryWins > awayCategoryWins ? .home
             : (awayCategoryWins > homeCategoryWins ? .away : .tie)
    }
}

/// Pure per-matchup scoring over already-resolved productions. Category formats compare
/// each category's summed z (higher wins); points formats compare `pointsPerGame`.
nonisolated enum FantasyMatchupScoring {

    static func score(home: UUID, away: UUID,
                      productions: [UUID: FantasyTeamProduction],
                      format: FantasyFormat,
                      customCategories: [FantasyLeagueCategory]? = nil) -> FantasyMatchupResult {
        let hp = productions[home] ?? .zero
        let ap = productions[away] ?? .zero

        // A custom category mask forces CATEGORY scoring even under a points
        // preset — a custom league is definitionally a category league.
        if format.isPoints && customCategories == nil {
            return FantasyMatchupResult(
                home: home, away: away, isPoints: true, lines: [],
                homeCategoryWins: 0, awayCategoryWins: 0, categoryTies: 0,
                homePoints: hp.pointsPerGame, awayPoints: ap.pointsPerGame)
        }

        let lines = FantasyLeagueCategory.active(format: format, custom: customCategories).map { c in
            FantasyCategoryLine(category: c,
                                homeZ: c.z(in: hp.categoryTotals),
                                awayZ: c.z(in: ap.categoryTotals))
        }
        let hw = lines.filter { $0.outcome == .home }.count
        let aw = lines.filter { $0.outcome == .away }.count
        let ties = lines.filter { $0.outcome == .tie }.count

        return FantasyMatchupResult(
            home: home, away: away, isPoints: false, lines: lines,
            homeCategoryWins: hw, awayCategoryWins: aw, categoryTies: ties,
            homePoints: 0, awayPoints: 0)
    }
}

/// A standings row: order + the primary metric + the accumulated head-to-head record.
nonisolated struct FantasyStandingRow: Equatable, Identifiable {
    let teamId: UUID
    let rank: Int             // 1-based, after sort
    let record: FantasyRecord // accumulated W-L-T (+ category tally / points-for)
    let rotoPoints: Double    // category formats (roto rank-sum); 0 for points
    let pointsPerGame: Double // points formats (static per-game roster strength); 0 for category
    var id: UUID { teamId }
}

/// Accumulated head-to-head record for one team across the whole schedule.
nonisolated struct FantasyRecord: Equatable {
    var wins = 0, losses = 0, ties = 0                          // matchup record
    var categoryWins = 0, categoryLosses = 0, categoryTies = 0  // summed category tally
    var pointsFor = 0.0                                          // summed points across matchups
}

nonisolated enum FantasyStandings {

    /// Full standings: score the schedule, accumulate records, compute the metric, and
    /// sort per the format rule above so the displayed order agrees with the W-L column.
    static func standings(productions: [UUID: FantasyTeamProduction],
                          teamIds: [UUID],
                          schedule: [FantasyScheduleWeek],
                          format: FantasyFormat,
                          customCategories: [FantasyLeagueCategory]? = nil) -> [FantasyStandingRow] {
        let recs = records(schedule: schedule, productions: productions, format: format,
                           customCategories: customCategories)
        let isPointsScoring = format.isPoints && customCategories == nil
        let roto = isPointsScoring
            ? [:] : rotoPoints(productions: productions, teamIds: teamIds, format: format,
                               customCategories: customCategories)

        func rec(_ id: UUID) -> FantasyRecord { recs[id] ?? .init() }
        func rotoOf(_ id: UUID) -> Double { roto[id] ?? 0 }
        func ppg(_ id: UUID) -> Double { (productions[id] ?? .zero).pointsPerGame }

        let sorted = teamIds.sorted { l, r in
            if isPointsScoring {
                let ml = ppg(l), mr = ppg(r)
                if ml != mr { return ml > mr }
            } else if format == .roto && customCategories == nil {
                let ml = rotoOf(l), mr = rotoOf(r)
                if ml != mr { return ml > mr }
            } else {                                        // H2H categories (incl. custom): sort BY record
                let rl = rec(l), rr = rec(r)
                if rl.wins != rr.wins { return rl.wins > rr.wins }
                let dl = rl.categoryWins - rl.categoryLosses
                let dr = rr.categoryWins - rr.categoryLosses
                if dl != dr { return dl > dr }
                let ml = rotoOf(l), mr = rotoOf(r)
                if ml != mr { return ml > mr }
            }
            return l.uuidString < r.uuidString              // deterministic final tiebreak
        }

        return sorted.enumerated().map { i, id in
            FantasyStandingRow(teamId: id, rank: i + 1, record: rec(id),
                               rotoPoints:   isPointsScoring ? 0 : rotoOf(id),
                               pointsPerGame: isPointsScoring ? ppg(id) : 0)
        }
    }

    /// Schedule-derived head-to-head record accumulation: score every scheduled matchup
    /// and tally each team's wins/losses/ties (+ category tally + points-for).
    static func records(schedule: [FantasyScheduleWeek],
                        productions: [UUID: FantasyTeamProduction],
                        format: FantasyFormat,
                        customCategories: [FantasyLeagueCategory]? = nil) -> [UUID: FantasyRecord] {
        var out: [UUID: FantasyRecord] = [:]
        for week in schedule {
            for p in week.pairings {
                let r = FantasyMatchupScoring.score(home: p.home, away: p.away,
                                                    productions: productions, format: format,
                                                    customCategories: customCategories)
                var h = out[p.home] ?? .init()
                var a = out[p.away] ?? .init()
                h.pointsFor += r.homePoints
                a.pointsFor += r.awayPoints
                if !r.isPoints {
                    h.categoryWins += r.homeCategoryWins; h.categoryLosses += r.awayCategoryWins
                    a.categoryWins += r.awayCategoryWins; a.categoryLosses += r.homeCategoryWins
                    h.categoryTies += r.categoryTies;     a.categoryTies += r.categoryTies
                }
                switch r.outcome {
                case .home: h.wins += 1;  a.losses += 1
                case .away: a.wins += 1;  h.losses += 1
                case .tie:  h.ties += 1;  a.ties += 1
                }
                out[p.home] = h; out[p.away] = a
            }
        }
        return out
    }

    /// Classic roto rank-sum: for each participating category, rank all teams (higher z =
    /// more roto points; ties share the AVERAGE of the tied ranks) and sum per team.
    static func rotoPoints(productions: [UUID: FantasyTeamProduction],
                           teamIds: [UUID],
                           format: FantasyFormat,
                           customCategories: [FantasyLeagueCategory]? = nil) -> [UUID: Double] {
        var out = Dictionary(uniqueKeysWithValues: teamIds.map { ($0, 0.0) })
        for c in FantasyLeagueCategory.active(format: format, custom: customCategories) {
            let vals = teamIds.map { c.z(in: (productions[$0] ?? .zero).categoryTotals) }
            for (idx, id) in teamIds.enumerated() {
                let v = vals[idx]
                let less  = vals.filter { $0 < v }.count      // teams strictly worse
                let equal = vals.filter { $0 == v }.count     // teams tied (incl. self)
                // average of the tied rank block: (1 + less) + (equal - 1)/2
                out[id, default: 0] += Double(1 + less) + Double(equal - 1) / 2.0
            }
        }
        return out
    }
}
