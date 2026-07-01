import Foundation

/// A per-player `fantasyActuals/{slug}` doc: season-to-date games played + per-game box
/// means + real fantasy points/game (ESPN/Yahoo, computed server-side with the shared
/// presets). Forgiving decode — every field defaults, so a partial doc still decodes and
/// unknown future keys are ignored. There is NO `slug` field; the store keys by documentID.
nonisolated struct FantasyActuals: Codable, Equatable, Hashable {
    let gp: Int
    let perGame: PerGame
    let fpPerGame: FpPerGame
    let season: String
    let asOf: String?

    enum CodingKeys: String, CodingKey { case gp, perGame, fpPerGame, season, asOf }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        gp        = try c.decodeIfPresent(Int.self,       forKey: .gp)        ?? 0
        perGame   = try c.decodeIfPresent(PerGame.self,   forKey: .perGame)   ?? .zero
        fpPerGame = try c.decodeIfPresent(FpPerGame.self, forKey: .fpPerGame) ?? .zero
        season    = try c.decodeIfPresent(String.self,    forKey: .season)    ?? ""
        asOf      = try c.decodeIfPresent(String.self,    forKey: .asOf)
    }
    init(gp: Int, perGame: PerGame, fpPerGame: FpPerGame, season: String, asOf: String?) {
        self.gp = gp; self.perGame = perGame; self.fpPerGame = fpPerGame
        self.season = season; self.asOf = asOf
    }

    /// Season-to-date per-game box means. Turnovers keyed `tov` (SP-0 stat key), matching
    /// `FantasyValue.ScoringMeans`. FG%/FT% are DERIVED by the source (volume-weighted).
    struct PerGame: Codable, Equatable, Hashable {
        let pts, reb, ast, stl, blk, tov, fg3m, fgm, fga, ftm, fta: Double
        enum CodingKeys: String, CodingKey { case pts, reb, ast, stl, blk, tov, fg3m, fgm, fga, ftm, fta }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pts  = try c.decodeIfPresent(Double.self, forKey: .pts)  ?? 0
            reb  = try c.decodeIfPresent(Double.self, forKey: .reb)  ?? 0
            ast  = try c.decodeIfPresent(Double.self, forKey: .ast)  ?? 0
            stl  = try c.decodeIfPresent(Double.self, forKey: .stl)  ?? 0
            blk  = try c.decodeIfPresent(Double.self, forKey: .blk)  ?? 0
            tov  = try c.decodeIfPresent(Double.self, forKey: .tov)  ?? 0
            fg3m = try c.decodeIfPresent(Double.self, forKey: .fg3m) ?? 0
            fgm  = try c.decodeIfPresent(Double.self, forKey: .fgm)  ?? 0
            fga  = try c.decodeIfPresent(Double.self, forKey: .fga)  ?? 0
            ftm  = try c.decodeIfPresent(Double.self, forKey: .ftm)  ?? 0
            fta  = try c.decodeIfPresent(Double.self, forKey: .fta)  ?? 0
        }
        init(pts: Double, reb: Double, ast: Double, stl: Double, blk: Double, tov: Double,
             fg3m: Double, fgm: Double, fga: Double, ftm: Double, fta: Double) {
            self.pts = pts; self.reb = reb; self.ast = ast; self.stl = stl; self.blk = blk
            self.tov = tov; self.fg3m = fg3m; self.fgm = fgm; self.fga = fga; self.ftm = ftm; self.fta = fta
        }
        static let zero = PerGame(pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, tov: 0,
                                  fg3m: 0, fgm: 0, fga: 0, ftm: 0, fta: 0)
    }

    struct FpPerGame: Codable, Equatable, Hashable {
        let espn, yahoo: Double
        enum CodingKeys: String, CodingKey { case espn, yahoo }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            espn  = try c.decodeIfPresent(Double.self, forKey: .espn)  ?? 0
            yahoo = try c.decodeIfPresent(Double.self, forKey: .yahoo) ?? 0
        }
        init(espn: Double, yahoo: Double) { self.espn = espn; self.yahoo = yahoo }
        static let zero = FpPerGame(espn: 0, yahoo: 0)
    }
}

/// The single `fantasyActuals/_meta` doc: season + count + asOf. Same defaulting pattern.
nonisolated struct FantasyActualsMeta: Codable, Equatable, Hashable {
    let season: String
    let count: Int
    let asOf: String?
    enum CodingKeys: String, CodingKey { case season, count, asOf }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        season = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
        count  = try c.decodeIfPresent(Int.self,    forKey: .count)  ?? 0
        asOf   = try c.decodeIfPresent(String.self, forKey: .asOf)
    }
    init(season: String, count: Int, asOf: String?) {
        self.season = season; self.count = count; self.asOf = asOf
    }
}
