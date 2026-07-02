import Foundation

/// Pure roster grading: a player's strength is his RANK PERCENTILE in the league
/// value pool under the active format (rank 1 = best), and a team's grade is the
/// mean percentile of its graded players mapped onto a standard letter curve.
/// Scale-free by construction — no tuned value thresholds to drift as the value
/// model evolves. Ranks come from the season-long `fantasyValues` docs, so the
/// grade reads "lineup strength vs the league pool" in both stat-source modes.
nonisolated enum FantasyGrading {

    /// Standard letter curve over a 0…1 percentile.
    static func letter(forPercentile p: Double) -> String {
        switch p {
        case 0.90...:       return "A+"
        case 0.80..<0.90:   return "A"
        case 0.70..<0.80:   return "B+"
        case 0.60..<0.70:   return "B"
        case 0.50..<0.60:   return "C+"
        case 0.40..<0.50:   return "C"
        case 0.30..<0.40:   return "D+"
        case 0.20..<0.30:   return "D"
        default:            return "F"
        }
    }

    /// Rank percentile in a pool: 1 → 1.0 (best), poolCount → 0.0. Degenerate
    /// pools (< 2 players) or out-of-range ranks grade nil rather than lying.
    static func percentile(rank: Int, poolCount: Int) -> Double? {
        guard poolCount > 1, rank >= 1, rank <= poolCount else { return nil }
        return 1.0 - Double(rank - 1) / Double(poolCount - 1)
    }

    /// Size of the RANKED population for a format — the percentile denominator.
    /// The value pipeline ranks only the top of the pool (e.g. 1…200 of 582
    /// docs; the rest carry rank nil), so the doc count would inflate grades.
    static func rankedPoolCount(values: [String: FantasyValue],
                                format: FantasyFormat) -> Int {
        values.values.reduce(0) { $0 + (format.entry(in: $1).rank != nil ? 1 : 0) }
    }

    /// Mean rank-percentile of the graded slugs. A player WITH a value doc but
    /// NO rank is known to sit below the ranked cut — he floors at 0.0 rather
    /// than silently inflating the average by vanishing. Players with no value
    /// doc at all (unknown) are skipped. nil when nobody grades or the ranked
    /// pool is degenerate.
    static func teamPercentile(slugs: [String],
                               values: [String: FantasyValue],
                               format: FantasyFormat,
                               poolCount: Int) -> Double? {
        guard poolCount > 1 else { return nil }
        let ps = slugs.compactMap { slug -> Double? in
            guard let fv = values[FantasyValueStore.canonicalSlug(slug)] else { return nil }
            guard let rank = format.entry(in: fv).rank else { return 0.0 }
            return percentile(rank: rank, poolCount: poolCount)
        }
        guard !ps.isEmpty else { return nil }
        return ps.reduce(0, +) / Double(ps.count)
    }
}

/// One player's expected line for tonight — his per-game averages from the ACTIVE
/// stat source (season-long projected means, or live season-to-date means). `fp`
/// carries fantasy points/game under the active points provider; nil for category
/// formats, where the pts/reb/ast trio is the story.
nonisolated struct FantasyForecastLine: Equatable {
    let slug: String
    let pts: Double
    let reb: Double
    let ast: Double
    let fp: Double?
}

nonisolated enum FantasyTodayForecast {

    static func line(slug: String,
                     source: StatSourceMode,
                     format: FantasyFormat,
                     values: [String: FantasyValue],
                     actuals: [String: FantasyActuals],
                     actualsSeason: String) -> FantasyForecastLine? {
        let canon = FantasyValueStore.canonicalSlug(slug)
        switch source {
        case .projected:
            guard let fv = values[canon] else { return nil }
            let m = fv.scoringMeans
            let fp = format.isPoints ? format.entry(in: fv).fpPerGame : nil
            return FantasyForecastLine(slug: canon, pts: m.pts, reb: m.reb, ast: m.ast, fp: fp)
        case .live:
            guard let a = actuals[canon], a.season == actualsSeason else { return nil }
            let g = a.perGame
            let fp: Double? = format.isPoints
                ? (format == .pointsYahoo ? a.fpPerGame.yahoo : a.fpPerGame.espn)
                : nil
            return FantasyForecastLine(slug: canon, pts: g.pts, reb: g.reb, ast: g.ast, fp: fp)
        }
    }
}
