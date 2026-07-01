import Foundation

/// A per-player `fantasyValues/{slug}` doc. Forward-compatible: every field defaults
/// (scalars -> 0, `dynastyFactor` -> 1.0, nested blocks -> `.zero`, optionals -> nil)
/// so a doc missing any field still decodes and unknown future keys are ignored — the
/// graceful per-doc decode in `FirestoreService.fetchFantasyValues` only drops a
/// genuinely malformed doc. There is NO `slug` field; the store keys by `documentID`.
nonisolated struct FantasyValue: Codable, Equatable, Hashable {
    let categoryZ: CategoryZ
    let formats: Formats
    let scoringMeans: ScoringMeans
    let dynastyFactor: Double
    let asOf: String?

    enum CodingKeys: String, CodingKey { case categoryZ, formats, scoringMeans, dynastyFactor, asOf }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        categoryZ     = try c.decodeIfPresent(CategoryZ.self,    forKey: .categoryZ)     ?? .zero
        formats       = try c.decodeIfPresent(Formats.self,      forKey: .formats)       ?? .zero
        scoringMeans  = try c.decodeIfPresent(ScoringMeans.self, forKey: .scoringMeans)  ?? .zero
        dynastyFactor = try c.decodeIfPresent(Double.self,       forKey: .dynastyFactor) ?? 1.0
        asOf          = try c.decodeIfPresent(String.self,       forKey: .asOf)
    }

    init(categoryZ: CategoryZ, formats: Formats, scoringMeans: ScoringMeans,
         dynastyFactor: Double, asOf: String?) {
        self.categoryZ = categoryZ; self.formats = formats; self.scoringMeans = scoringMeans
        self.dynastyFactor = dynastyFactor; self.asOf = asOf
    }

    /// 9-category z-vector. Turnovers keyed `to` (category convention) and already
    /// sign-flipped server-side (positive `to`-z = good).
    struct CategoryZ: Codable, Equatable, Hashable {
        let pts, reb, ast, stl, blk, to, fg3m, fgPct, ftPct: Double
        enum CodingKeys: String, CodingKey { case pts, reb, ast, stl, blk, to, fg3m, fgPct, ftPct }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pts   = try c.decodeIfPresent(Double.self, forKey: .pts)   ?? 0
            reb   = try c.decodeIfPresent(Double.self, forKey: .reb)   ?? 0
            ast   = try c.decodeIfPresent(Double.self, forKey: .ast)   ?? 0
            stl   = try c.decodeIfPresent(Double.self, forKey: .stl)   ?? 0
            blk   = try c.decodeIfPresent(Double.self, forKey: .blk)   ?? 0
            to    = try c.decodeIfPresent(Double.self, forKey: .to)    ?? 0
            fg3m  = try c.decodeIfPresent(Double.self, forKey: .fg3m)  ?? 0
            fgPct = try c.decodeIfPresent(Double.self, forKey: .fgPct) ?? 0
            ftPct = try c.decodeIfPresent(Double.self, forKey: .ftPct) ?? 0
        }
        init(pts: Double, reb: Double, ast: Double, stl: Double, blk: Double,
             to: Double, fg3m: Double, fgPct: Double, ftPct: Double) {
            self.pts = pts; self.reb = reb; self.ast = ast; self.stl = stl; self.blk = blk
            self.to = to; self.fg3m = fg3m; self.fgPct = fgPct; self.ftPct = ftPct
        }
        static let zero = CategoryZ(pts: 0, reb: 0, ast: 0, stl: 0, blk: 0,
                                    to: 0, fg3m: 0, fgPct: 0, ftPct: 0)
    }

    struct Formats: Codable, Equatable, Hashable {
        let nineCat, eightCat, roto: FormatEntry
        let points: PointsFormats
        enum CodingKeys: String, CodingKey { case nineCat, eightCat, roto, points }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            nineCat  = try c.decodeIfPresent(FormatEntry.self,   forKey: .nineCat)  ?? .zero
            eightCat = try c.decodeIfPresent(FormatEntry.self,   forKey: .eightCat) ?? .zero
            roto     = try c.decodeIfPresent(FormatEntry.self,   forKey: .roto)     ?? .zero
            points   = try c.decodeIfPresent(PointsFormats.self, forKey: .points)   ?? .zero
        }
        init(nineCat: FormatEntry, eightCat: FormatEntry, roto: FormatEntry, points: PointsFormats) {
            self.nineCat = nineCat; self.eightCat = eightCat; self.roto = roto; self.points = points
        }
        static let zero = Formats(nineCat: .zero, eightCat: .zero, roto: .zero, points: .zero)
    }

    struct FormatEntry: Codable, Equatable, Hashable {
        let value: Double
        let rank: Int?
        enum CodingKeys: String, CodingKey { case value, rank }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
            rank  = try c.decodeIfPresent(Int.self,    forKey: .rank)
        }
        init(value: Double, rank: Int?) { self.value = value; self.rank = rank }
        static let zero = FormatEntry(value: 0, rank: nil)
    }

    struct PointsFormats: Codable, Equatable, Hashable {
        let espn, yahoo: PointsEntry
        enum CodingKeys: String, CodingKey { case espn, yahoo }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            espn  = try c.decodeIfPresent(PointsEntry.self, forKey: .espn)  ?? .zero
            yahoo = try c.decodeIfPresent(PointsEntry.self, forKey: .yahoo) ?? .zero
        }
        init(espn: PointsEntry, yahoo: PointsEntry) { self.espn = espn; self.yahoo = yahoo }
        static let zero = PointsFormats(espn: .zero, yahoo: .zero)
    }

    struct PointsEntry: Codable, Equatable, Hashable {
        let fpPerGame, value: Double
        let rank: Int?
        enum CodingKeys: String, CodingKey { case fpPerGame, value, rank }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            fpPerGame = try c.decodeIfPresent(Double.self, forKey: .fpPerGame) ?? 0
            value     = try c.decodeIfPresent(Double.self, forKey: .value)     ?? 0
            rank      = try c.decodeIfPresent(Int.self,    forKey: .rank)
        }
        init(fpPerGame: Double, value: Double, rank: Int?) {
            self.fpPerGame = fpPerGame; self.value = value; self.rank = rank
        }
        static let zero = PointsEntry(fpPerGame: 0, value: 0, rank: nil)
    }

    /// Projected per-game means. Turnovers keyed `tov` here (SP-1 stat key) vs `to`
    /// in `categoryZ` — same quantity, two spellings. FG%/FT% are DERIVED.
    struct ScoringMeans: Codable, Equatable, Hashable {
        let pts, fg3m, fgm, fga, ftm, fta, reb, ast, stl, blk, tov: Double
        enum CodingKeys: String, CodingKey { case pts, fg3m, fgm, fga, ftm, fta, reb, ast, stl, blk, tov }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            pts  = try c.decodeIfPresent(Double.self, forKey: .pts)  ?? 0
            fg3m = try c.decodeIfPresent(Double.self, forKey: .fg3m) ?? 0
            fgm  = try c.decodeIfPresent(Double.self, forKey: .fgm)  ?? 0
            fga  = try c.decodeIfPresent(Double.self, forKey: .fga)  ?? 0
            ftm  = try c.decodeIfPresent(Double.self, forKey: .ftm)  ?? 0
            fta  = try c.decodeIfPresent(Double.self, forKey: .fta)  ?? 0
            reb  = try c.decodeIfPresent(Double.self, forKey: .reb)  ?? 0
            ast  = try c.decodeIfPresent(Double.self, forKey: .ast)  ?? 0
            stl  = try c.decodeIfPresent(Double.self, forKey: .stl)  ?? 0
            blk  = try c.decodeIfPresent(Double.self, forKey: .blk)  ?? 0
            tov  = try c.decodeIfPresent(Double.self, forKey: .tov)  ?? 0
        }
        init(pts: Double, fg3m: Double, fgm: Double, fga: Double, ftm: Double, fta: Double,
             reb: Double, ast: Double, stl: Double, blk: Double, tov: Double) {
            self.pts = pts; self.fg3m = fg3m; self.fgm = fgm; self.fga = fga; self.ftm = ftm
            self.fta = fta; self.reb = reb; self.ast = ast; self.stl = stl; self.blk = blk; self.tov = tov
        }
        var fgPct: Double? { fga > 0 ? fgm / fga : nil }
        var ftPct: Double? { fta > 0 ? ftm / fta : nil }
        static let zero = ScoringMeans(pts: 0, fg3m: 0, fgm: 0, fga: 0, ftm: 0, fta: 0,
                                       reb: 0, ast: 0, stl: 0, blk: 0, tov: 0)
    }
}

/// The single `fantasyValues/_meta` doc: pool aggregates + per-format replacement
/// levels (the dynasty value-above-replacement basis). Same defaulting pattern.
nonisolated struct FantasyMeta: Codable, Equatable, Hashable {
    let pool: Pool
    let replacement: Replacement
    let count: Int
    let asOf: String?

    enum CodingKeys: String, CodingKey { case pool, replacement, count, asOf }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pool        = try c.decodeIfPresent(Pool.self,        forKey: .pool)        ?? .zero
        replacement = try c.decodeIfPresent(Replacement.self, forKey: .replacement) ?? .zero
        count       = try c.decodeIfPresent(Int.self,         forKey: .count)       ?? 0
        asOf        = try c.decodeIfPresent(String.self,      forKey: .asOf)
    }
    init(pool: Pool, replacement: Replacement, count: Int, asOf: String?) {
        self.pool = pool; self.replacement = replacement; self.count = count; self.asOf = asOf
    }

    struct Pool: Codable, Equatable, Hashable {
        let minMinutes: Double
        let size, replacementRank, nRanked: Int
        let leagueFGpct, leagueFTpct: Double
        enum CodingKeys: String, CodingKey {
            case minMinutes, size, replacementRank, nRanked, leagueFGpct, leagueFTpct
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            minMinutes      = try c.decodeIfPresent(Double.self, forKey: .minMinutes)      ?? 0
            size            = try c.decodeIfPresent(Int.self,    forKey: .size)            ?? 0
            replacementRank = try c.decodeIfPresent(Int.self,    forKey: .replacementRank) ?? 0
            nRanked         = try c.decodeIfPresent(Int.self,    forKey: .nRanked)         ?? 0
            leagueFGpct     = try c.decodeIfPresent(Double.self, forKey: .leagueFGpct)     ?? 0
            leagueFTpct     = try c.decodeIfPresent(Double.self, forKey: .leagueFTpct)     ?? 0
        }
        init(minMinutes: Double, size: Int, replacementRank: Int, nRanked: Int,
             leagueFGpct: Double, leagueFTpct: Double) {
            self.minMinutes = minMinutes; self.size = size; self.replacementRank = replacementRank
            self.nRanked = nRanked; self.leagueFGpct = leagueFGpct; self.leagueFTpct = leagueFTpct
        }
        static let zero = Pool(minMinutes: 0, size: 0, replacementRank: 0, nRanked: 0,
                               leagueFGpct: 0, leagueFTpct: 0)
    }

    struct Replacement: Codable, Equatable, Hashable {
        let nineCat, eightCat, roto: Double
        let points: PointsReplacement
        enum CodingKeys: String, CodingKey { case nineCat, eightCat, roto, points }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            nineCat  = try c.decodeIfPresent(Double.self, forKey: .nineCat)  ?? 0
            eightCat = try c.decodeIfPresent(Double.self, forKey: .eightCat) ?? 0
            roto     = try c.decodeIfPresent(Double.self, forKey: .roto)     ?? 0
            points   = try c.decodeIfPresent(PointsReplacement.self, forKey: .points) ?? .zero
        }
        init(nineCat: Double, eightCat: Double, roto: Double, points: PointsReplacement) {
            self.nineCat = nineCat; self.eightCat = eightCat; self.roto = roto; self.points = points
        }
        static let zero = Replacement(nineCat: 0, eightCat: 0, roto: 0, points: .zero)
    }

    struct PointsReplacement: Codable, Equatable, Hashable {
        let espn, yahoo: Double
        enum CodingKeys: String, CodingKey { case espn, yahoo }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            espn  = try c.decodeIfPresent(Double.self, forKey: .espn)  ?? 0
            yahoo = try c.decodeIfPresent(Double.self, forKey: .yahoo) ?? 0
        }
        init(espn: Double, yahoo: Double) { self.espn = espn; self.yahoo = yahoo }
        static let zero = PointsReplacement(espn: 0, yahoo: 0)
    }
}
