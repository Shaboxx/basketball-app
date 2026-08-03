import Foundation

/// One ranked team row: rank (1-based), the team, its five starters ordered
/// PG->C, and the Σ dispTotal ranking metric. `Hashable` so it can drive a
/// `navigationDestination(for: LineupRankRow.self)` (synthesized — Team and
/// Player are both Hashable).
nonisolated struct LineupRankRow: Identifiable, Hashable {
    let rank: Int
    let team: Team
    let starters: [Player]   // ordered PG, SG, SF, PF, C
    let total: Double
    var id: String { team.teamId }
}

/// Ranked rows plus the teams dropped for incomplete data (surfaced honestly).
nonisolated struct LineupRankingResult: Equatable {
    let ranked: [LineupRankRow]
    let excluded: [Team]     // sorted by fullName asc
}

/// Pure, testable ranking of every team's depth-chart layer-0 starting five by
/// Σ `dispTotal`. No SwiftUI; runs off in-memory rosters.
nonisolated enum LineupRankingLogic {

    /// Layer-0 starter per position (PG->C) from the depth chart, or nil for a
    /// position with no filled layer-0 cell.
    static func starters(for roster: [Player]) -> [Player?] {
        let columns = TeamDepthChartBuilder.columns(for: roster)
        return TeamDepthChartBuilder.positions.map { columns[$0]?.shown.first?.player }
    }

    /// Rank all teams. A team is EXCLUDED when any of its five starter slots is
    /// empty OR any starter's `dispTotal` is nil (avoids a zero-filled team
    /// ranking falsely low). Ranked desc by total, name asc tie-break; excluded
    /// sorted by name asc.
    static func rank(teams: [Team],
                     rostersByTeamId: [String: [Player]]) -> LineupRankingResult {
        var complete: [(team: Team, starters: [Player], total: Double)] = []
        var excluded: [Team] = []

        for team in teams {
            let roster = rostersByTeamId[team.teamId] ?? []
            let slots = starters(for: roster)
            let filled = slots.compactMap { $0 }
            let totals = filled.map { $0.dispTotal }
            if filled.count == TeamDepthChartBuilder.positions.count,
               totals.allSatisfy({ $0 != nil }) {
                let total = totals.reduce(0.0) { $0 + ($1 ?? 0) }
                complete.append((team, filled, total))
            } else {
                excluded.append(team)
            }
        }

        let sorted = complete.sorted {
            $0.total != $1.total ? $0.total > $1.total
                                 : $0.team.fullName < $1.team.fullName
        }
        let ranked = sorted.enumerated().map { i, e in
            LineupRankRow(rank: i + 1, team: e.team, starters: e.starters, total: e.total)
        }
        return LineupRankingResult(ranked: ranked,
                                   excluded: excluded.sorted { $0.fullName < $1.fullName })
    }
}
