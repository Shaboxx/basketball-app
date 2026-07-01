import Foundation

/// Live season-to-date source: emits the SAME `FantasyTeamProduction` as
/// `ProjectedStatSource`, but from real per-game actuals. PURE + nonisolated — it holds a
/// plain `[String: FantasyActuals]` SNAPSHOT (the view passes `store.actualsBySlug` on
/// MainActor; tests pass a fixture), so nothing crosses isolation. Store misses are dropped
/// (a slug with no actuals contributes 0), matching `ProjectedStatSource`. Season-filtered:
/// a resolved doc from a different season is skipped.
///
/// The standings/matchup engine is SCALE-INVARIANT (it only ranks/counts per-category
/// orderings and compares points — never sums categories across each other, never uses
/// absolute magnitude), so RAW per-game rates drop straight into `CategoryZ` with NO
/// z-scoring. Two sign/shape rules make the raw rates engine-correct:
///   • `to` is INVERTED (`-Σ tov`) because every `CategoryZ` field is "higher is better";
///   • FG%/FT% are VOLUME-WEIGHTED team aggregates (Σfgm/Σfga, Σftm/Σfta), NOT a sum of
///     per-player ratios (which would over-weight low-volume shooters).
/// Counting cats (pts/reb/ast/stl/blk/fg3m) are plain roster sums of per-game means.
nonisolated struct ActualsStatSource: FantasyStatSource {
    /// canonical-slug → FantasyActuals snapshot.
    let actuals: [String: FantasyActuals]
    /// The active season; a resolved doc from another season is skipped.
    let season: String

    init(actuals: [String: FantasyActuals], season: String) {
        self.actuals = actuals; self.season = season
    }

    func production(for team: FantasyTeam, format: FantasyFormat) -> FantasyTeamProduction {
        let roster = team.playerSlugs
            .compactMap { actuals[FantasyValueStore.canonicalSlug($0)] }
            .filter { $0.season == season }
        guard !roster.isEmpty else { return .zero }   // whole roster unresolved → zero (see §7 / §10)

        var pts = 0.0, reb = 0.0, ast = 0.0, stl = 0.0, blk = 0.0, tov = 0.0, fg3m = 0.0
        var fgm = 0.0, fga = 0.0, ftm = 0.0, fta = 0.0
        for a in roster {
            let g = a.perGame
            pts += g.pts; reb += g.reb; ast += g.ast; stl += g.stl; blk += g.blk
            tov += g.tov; fg3m += g.fg3m; fgm += g.fgm; fga += g.fga; ftm += g.ftm; fta += g.fta
        }

        let totals = FantasyValue.CategoryZ(
            pts: pts, reb: reb, ast: ast, stl: stl, blk: blk,
            to: -tov,                                       // INVERT: higher is better
            fg3m: fg3m,
            fgPct: fga > 0 ? fgm / fga : 0,                 // volume-weighted; guard 0 attempts
            ftPct: fta > 0 ? ftm / fta : 0)

        let ppg: Double = {
            switch format {
            case .pointsEspn:  return roster.reduce(0) { $0 + $1.fpPerGame.espn }
            case .pointsYahoo: return roster.reduce(0) { $0 + $1.fpPerGame.yahoo }
            default:           return 0                     // category formats score on categoryTotals
            }
        }()

        return FantasyTeamProduction(categoryTotals: totals, pointsPerGame: ppg)
    }
}
