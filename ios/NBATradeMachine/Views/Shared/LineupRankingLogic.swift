import Foundation

/// One ranked team row: rank (1-based), the team, its five starters ordered
/// PG->C, the Σ dispTotal ranking metric, plus Σ dispOff and Σ dispDef.
/// `off` and `def` are nil when at least one starter has no dispOff/dispDef
/// data — the team is still ranked by `total`.
/// `Hashable` so it can drive a `navigationDestination(for: LineupRankRow.self)`
/// (synthesized — Team and Player are both Hashable).
struct LineupRankRow: Identifiable, Hashable {
    let rank: Int
    let team: Team
    let starters: [Player]   // ordered PG, SG, SF, PF, C
    let total: Double
    let off: Double?         // Σ dispOff of starters; nil if any starter lacks dispOff
    let def: Double?         // Σ dispDef of starters; nil if any starter lacks dispDef
    var id: String { team.teamId }
}

/// Ranked rows plus the teams dropped for incomplete data (surfaced honestly).
struct LineupRankingResult: Equatable {
    let ranked: [LineupRankRow]
    let excluded: [Team]     // sorted by fullName asc
}

/// Testable ranking of every team's depth-chart layer-0 starting five by
/// Σ `dispTotal`. No SwiftUI, but `@MainActor` because its inputs
/// (`TeamDepthChartBuilder.columns`/`.positions`, `Player.dispTotal`) are
/// MainActor-isolated in this MainActor-default target; the ranking already
/// runs on the main actor (View body / in-memory roster).
@MainActor enum LineupRankingLogic {

    /// Layer-0 starter per position (PG->C) from the depth chart, or nil for a
    /// position with no filled layer-0 cell.
    static func starters(for roster: [Player]) -> [Player?] {
        let columns = TeamDepthChartBuilder.columns(for: roster)
        return TeamDepthChartBuilder.positions.map { columns[$0]?.shown.first?.player }
    }

    /// Rank all teams. A team is EXCLUDED only when any of its five starter slots
    /// is empty OR any starter's `dispTotal` is nil. Missing `dispOff`/`dispDef`
    /// does NOT exclude a team — those axes become nil on the row instead.
    /// Ranked desc by total; name then teamId asc as tie-breaks.
    /// Excluded sorted by name then teamId asc.
    static func rank(teams: [Team],
                     rostersByTeamId: [String: [Player]]) -> LineupRankingResult {
        var complete: [(team: Team, starters: [Player], total: Double, off: Double?, def: Double?)] = []
        var excluded: [Team] = []

        for team in teams {
            let roster = rostersByTeamId[team.teamId] ?? []
            let slots = starters(for: roster)
            let filled = slots.compactMap { $0 }
            let totals = filled.map { $0.dispTotal }
            let offs   = filled.map { $0.dispOff }
            let defs   = filled.map { $0.dispDef }

            guard filled.count == TeamDepthChartBuilder.positions.count,
                  totals.allSatisfy({ $0 != nil }) else {
                excluded.append(team)
                continue
            }

            let total = totals.compactMap { $0 }.reduce(0, +)
            let off: Double? = offs.allSatisfy({ $0 != nil })
                ? offs.compactMap({ $0 }).reduce(0, +)
                : nil
            let def: Double? = defs.allSatisfy({ $0 != nil })
                ? defs.compactMap({ $0 }).reduce(0, +)
                : nil
            complete.append((team, filled, total, off, def))
        }

        let sorted = complete.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            if $0.team.fullName != $1.team.fullName { return $0.team.fullName < $1.team.fullName }
            return $0.team.teamId < $1.team.teamId
        }
        let ranked = sorted.enumerated().map { i, e in
            LineupRankRow(rank: i + 1, team: e.team, starters: e.starters,
                          total: e.total, off: e.off, def: e.def)
        }
        return LineupRankingResult(
            ranked: ranked,
            excluded: excluded.sorted {
                $0.fullName != $1.fullName ? $0.fullName < $1.fullName : $0.teamId < $1.teamId
            }
        )
    }
}
