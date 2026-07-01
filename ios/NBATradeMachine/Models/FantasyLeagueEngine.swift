import Foundation

/// The 9 scoring categories, with the label set that matches `FantasyCategoryOrder`
/// ("PTS","REB","AST","STL","BLK","TO","3PM","FG%","FT%") and an accessor into a
/// summed `CategoryZ`. Turnovers (`to`) are already sign-flipped server-side
/// (positive z = good), so EVERY category is "higher z is better" — no special-casing.
nonisolated enum FantasyLeagueCategory: CaseIterable {
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
                      format: FantasyFormat) -> FantasyMatchupResult {
        let hp = productions[home] ?? .zero
        let ap = productions[away] ?? .zero

        if format.isPoints {
            return FantasyMatchupResult(
                home: home, away: away, isPoints: true, lines: [],
                homeCategoryWins: 0, awayCategoryWins: 0, categoryTies: 0,
                homePoints: hp.pointsPerGame, awayPoints: ap.pointsPerGame)
        }

        let lines = FantasyLeagueCategory.categories(for: format).map { c in
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
