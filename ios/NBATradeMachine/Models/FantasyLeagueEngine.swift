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
