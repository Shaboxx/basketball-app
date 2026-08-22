import Foundation

// MARK: - WeekTotals

/// Accumulated box-score totals for all games a player (or roster) played
/// inside a specific week interval. All counting stats are simple sums;
/// fgm/fga/ftm/fta are also summed so the caller can volume-weight FG%/FT%.
/// `gamesPlayed` counts only non-missed games whose date fell inside the interval.
nonisolated struct WeekTotals: Equatable {
    var pts: Int = 0
    var reb: Int = 0
    var ast: Int = 0
    var stl: Int = 0
    var blk: Int = 0
    var tov: Int = 0
    var fg3m: Int = 0
    var fgm: Int = 0
    var fga: Int = 0
    var ftm: Int = 0
    var fta: Int = 0
    var gamesPlayed: Int = 0

    static let zero = WeekTotals()
}

// MARK: - FantasyPointsWeights

/// Standard ESPN and Yahoo points-league scoring weights, hardcoded per spec §5.
/// Returns 0 for category formats (nineCat / eightCat / roto) — those formats
/// never use a points scalar. The caller supplies a complete `GameLine` (with
/// volume stats) so FG%/FT% columns are naturally 0 for points formats.
nonisolated enum FantasyPointsWeights {

    /// Fantasy points for one `GameLine` under `format`. Returns 0 for non-points
    /// formats or missed games. Nil stat fields are treated as 0.
    static func points(for line: GameLine, format: FantasyFormat) -> Double {
        guard !line.missed else { return 0 }
        switch format {
        case .pointsEspn:
            // pts 1, reb 1, ast 1, stl 2, blk 2, tov −1, fg3m 1
            let ePts  = Double(line.pts  ?? 0)
            let eReb  = Double(line.reb  ?? 0)
            let eAst  = Double(line.ast  ?? 0)
            let eStl  = Double(line.stl  ?? 0) * 2.0
            let eBlk  = Double(line.blk  ?? 0) * 2.0
            let eTov  = Double(line.tov  ?? 0) * -1.0
            let eFg3m = Double(line.fg3m ?? 0)
            return ePts + eReb + eAst + eStl + eBlk + eTov + eFg3m
        case .pointsYahoo:
            // pts 1, reb 1.2, ast 1.5, stl 3, blk 3, tov −1
            let yPts = Double(line.pts ?? 0)
            let yReb = Double(line.reb ?? 0) * 1.2
            let yAst = Double(line.ast ?? 0) * 1.5
            let yStl = Double(line.stl ?? 0) * 3.0
            let yBlk = Double(line.blk ?? 0) * 3.0
            let yTov = Double(line.tov ?? 0) * -1.0
            return yPts + yReb + yAst + yStl + yBlk + yTov
        case .nineCat, .eightCat, .roto:
            return 0
        }
    }
}

// MARK: - FantasyWeekAggregator

/// Pure, nonisolated aggregation of a player's game-log lines into a `WeekTotals`
/// for a specific week interval. Used by the weekly H2H engine to compute per-player
/// weekly contributions before team-level aggregation.
nonisolated enum FantasyWeekAggregator {

    // DateFormatter is not Sendable, so we build one per call (lightweight).
    private static func makeDateFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = FantasyCalendar.zone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    /// Aggregate `games` whose date falls inside `interval` (inclusive of both
    /// endpoints as start-of-day boundaries). Missed games are always skipped.
    ///
    /// - Parameters:
    ///   - games: The full array from `PlayerGameLogSeason.games`.
    ///   - interval: A closed interval [start, end). A game whose parsed
    ///     start-of-day date satisfies `start <= gameDay < end` is included.
    ///     This matches the half-open convention used by `FantasyCalendar.weekDateRange`.
    /// - Returns: Summed `WeekTotals` for qualifying games.
    static func weeklyLine(games: [GameLine], in interval: DateInterval) -> WeekTotals {
        let fmt = makeDateFormatter()
        var totals = WeekTotals()
        for game in games {
            guard !game.missed else { continue }
            guard let gameDate = fmt.date(from: game.date) else { continue }
            // gameDate is already start-of-day in the league zone (DateFormatter with
            // timeZone set returns midnight in that zone). The interval is [start, end).
            guard gameDate >= interval.start && gameDate < interval.end else { continue }

            totals.pts  += game.pts  ?? 0
            totals.reb  += game.reb  ?? 0
            totals.ast  += game.ast  ?? 0
            totals.stl  += game.stl  ?? 0
            totals.blk  += game.blk  ?? 0
            totals.tov  += game.tov  ?? 0
            totals.fg3m += game.fg3m ?? 0
            totals.fgm  += game.fgm  ?? 0
            totals.fga  += game.fga  ?? 0
            totals.ftm  += game.ftm  ?? 0
            totals.fta  += game.fta  ?? 0
            totals.gamesPlayed += 1
        }
        return totals
    }
}
