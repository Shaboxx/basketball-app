import Foundation

/// One player's raw per-game line, UNIFIED across projected means and live actuals
/// so Dream Team scoring reads from either source identically. `fp` is the fantasy
/// points/game under the active points provider (0 for category formats).
nonisolated struct RawPerGame: Equatable {
    let pts, reb, ast, stl, blk, tov, fg3m, fgm, fga, ftm, fta, fp: Double

    static let zero = RawPerGame(pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, tov: 0,
                                 fg3m: 0, fgm: 0, fga: 0, ftm: 0, fta: 0, fp: 0)

    /// Projected: the player's season-long means + the active points format's fp/game.
    static func projected(_ fv: FantasyValue, format: FantasyFormat) -> RawPerGame {
        let m = fv.scoringMeans
        return RawPerGame(pts: m.pts, reb: m.reb, ast: m.ast, stl: m.stl, blk: m.blk,
                          tov: m.tov, fg3m: m.fg3m, fgm: m.fgm, fga: m.fga, ftm: m.ftm, fta: m.fta,
                          fp: format.isPoints ? (format.entry(in: fv).fpPerGame ?? 0) : 0)
    }

    /// Live: the player's season-to-date per-game box means + fp/game.
    static func live(_ a: FantasyActuals, format: FantasyFormat) -> RawPerGame {
        let g = a.perGame
        let fp = format.isPoints ? (format == .pointsYahoo ? a.fpPerGame.yahoo : a.fpPerGame.espn) : 0
        return RawPerGame(pts: g.pts, reb: g.reb, ast: g.ast, stl: g.stl, blk: g.blk,
                          tov: g.tov, fg3m: g.fg3m, fgm: g.fgm, fga: g.fga, ftm: g.ftm, fta: g.fta, fp: fp)
    }
}

/// Pure Dream Team scoring: a player rostered by N teams in the league contributes
/// only 1/N of his COUNTING stats to each team (a 30-point night shared by 3 teams
/// gives each team 10). Percentages are volume-weighted on the DIVIDED makes/attempts,
/// so a heavily-shared player's shooting naturally counts for less of the team's
/// volume. Produces the same `FantasyTeamProduction` shape as the standard sources,
/// so the standings/matchup engine is untouched.
nonisolated enum FantasyDreamTeamScoring {

    /// How many member teams roster each canonical slug (a team counts a player once).
    static func ownership(teams: [FantasyTeam]) -> [String: Int] {
        var out: [String: Int] = [:]
        for team in teams {
            for slug in Set(team.playerSlugs.map(FantasyValueStore.canonicalSlug)) {
                out[slug, default: 0] += 1
            }
        }
        return out
    }

    /// Productions keyed by team id, each summing every player's per-game line DIVIDED
    /// by his league ownership count. `raw(canonicalSlug)` returns the player's line, or
    /// nil (unresolved → contributes nothing).
    static func productions(teams: [FantasyTeam],
                            ownership: [String: Int],
                            raw: (String) -> RawPerGame?) -> [UUID: FantasyTeamProduction] {
        var out: [UUID: FantasyTeamProduction] = [:]
        for team in teams {
            var pts = 0.0, reb = 0.0, ast = 0.0, stl = 0.0, blk = 0.0, tov = 0.0, fg3m = 0.0
            var fgm = 0.0, fga = 0.0, ftm = 0.0, fta = 0.0, fp = 0.0
            // Dedup per team (symmetric with `ownership`) so a duplicated slug in a
            // tampered/migrated blob can't double-dip its divided contribution.
            for canon in Set(team.playerSlugs.map(FantasyValueStore.canonicalSlug)) {
                guard let r = raw(canon) else { continue }
                let own = Double(max(1, ownership[canon] ?? 1))
                pts += r.pts / own; reb += r.reb / own; ast += r.ast / own
                stl += r.stl / own; blk += r.blk / own; tov += r.tov / own; fg3m += r.fg3m / own
                fgm += r.fgm / own; fga += r.fga / own; ftm += r.ftm / own; fta += r.fta / own
                fp  += r.fp / own
            }
            let totals = FantasyValue.CategoryZ(
                pts: pts, reb: reb, ast: ast, stl: stl, blk: blk,
                to: -tov,                                    // INVERT: higher is better
                fg3m: fg3m,
                fgPct: fga > 0 ? fgm / fga : 0,              // volume-weighted on divided attempts
                ftPct: fta > 0 ? ftm / fta : 0)
            out[team.id] = FantasyTeamProduction(categoryTotals: totals, pointsPerGame: fp)
        }
        return out
    }
}
