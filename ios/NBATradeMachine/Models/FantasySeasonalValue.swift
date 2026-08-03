import Foundation

/// A per-player `fantasySeasonalValues/{slug}` doc: the SP-4 "Rdur" projected seasonal fantasy
/// value (ESPN points season total) decomposed into its two validated signals — talent
/// (last-season fantasy points/game) and durability (expected games = EB games-played rate × 82).
/// `projectedSeasonTotal ≈ talentFpPerGame × expectedGames`. Forgiving decode — every field
/// defaults, so a partial doc still decodes and unknown future keys are ignored. There is NO
/// `slug` field; the store keys by documentID. `season` is carried so the store can reject a
/// stale-season straggler after a rollover (see FantasyValueStore.seasonalValue).
nonisolated struct FantasySeasonalValue: Codable, Equatable, Hashable {
    let projectedSeasonTotal: Double
    let projectedSeasonTotalLow: Double
    let projectedSeasonTotalHigh: Double
    let talentFpPerGame: Double
    let expectedGames: Double
    let expectedGamesLow: Double
    let expectedGamesHigh: Double
    let expectedGpRate: Double
    let lastGpRate: Double
    let age: Int?
    let season: String
    let asOf: String?

    enum CodingKeys: String, CodingKey {
        case projectedSeasonTotal, projectedSeasonTotalLow, projectedSeasonTotalHigh
        case talentFpPerGame, expectedGames, expectedGamesLow, expectedGamesHigh
        case expectedGpRate, lastGpRate, age, season, asOf
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        projectedSeasonTotal     = try c.decodeIfPresent(Double.self, forKey: .projectedSeasonTotal)     ?? 0
        projectedSeasonTotalLow  = try c.decodeIfPresent(Double.self, forKey: .projectedSeasonTotalLow)  ?? 0
        projectedSeasonTotalHigh = try c.decodeIfPresent(Double.self, forKey: .projectedSeasonTotalHigh) ?? 0
        talentFpPerGame          = try c.decodeIfPresent(Double.self, forKey: .talentFpPerGame)          ?? 0
        expectedGames            = try c.decodeIfPresent(Double.self, forKey: .expectedGames)            ?? 0
        expectedGamesLow         = try c.decodeIfPresent(Double.self, forKey: .expectedGamesLow)         ?? 0
        expectedGamesHigh        = try c.decodeIfPresent(Double.self, forKey: .expectedGamesHigh)        ?? 0
        expectedGpRate           = try c.decodeIfPresent(Double.self, forKey: .expectedGpRate)           ?? 0
        lastGpRate               = try c.decodeIfPresent(Double.self, forKey: .lastGpRate)               ?? 0
        age                      = try c.decodeIfPresent(Int.self,    forKey: .age)
        season                   = try c.decodeIfPresent(String.self, forKey: .season)                  ?? ""
        asOf                     = try c.decodeIfPresent(String.self, forKey: .asOf)
    }
    init(projectedSeasonTotal: Double, projectedSeasonTotalLow: Double = 0, projectedSeasonTotalHigh: Double = 0,
         talentFpPerGame: Double, expectedGames: Double, expectedGamesLow: Double = 0, expectedGamesHigh: Double = 0,
         expectedGpRate: Double, lastGpRate: Double, age: Int?, season: String, asOf: String?) {
        self.projectedSeasonTotal = projectedSeasonTotal
        self.projectedSeasonTotalLow = projectedSeasonTotalLow; self.projectedSeasonTotalHigh = projectedSeasonTotalHigh
        self.talentFpPerGame = talentFpPerGame
        self.expectedGames = expectedGames
        self.expectedGamesLow = expectedGamesLow; self.expectedGamesHigh = expectedGamesHigh
        self.expectedGpRate = expectedGpRate
        self.lastGpRate = lastGpRate; self.age = age; self.season = season; self.asOf = asOf
    }

    /// Formats "lo–hi" if a valid range is present (fresh docs), else falls back to the point value
    /// (old docs whose range fields default to 0). `digits` controls decimals; thousands-grouped.
    private static func rangeText(_ point: Double, _ lo: Double, _ hi: Double, digits: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = digits; f.minimumFractionDigits = digits
        func s(_ v: Double) -> String { f.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v) }
        return (hi > lo && lo >= 0) ? "\(s(lo))–\(s(hi))" : s(point)
    }
    /// "3,600–4,800" fantasy points (or the point value if no range).
    var projectedSeasonTotalText: String {
        Self.rangeText(projectedSeasonTotal, projectedSeasonTotalLow, projectedSeasonTotalHigh, digits: 0)
    }
    /// "58–76" games (or the point value if no range).
    var expectedGamesText: String {
        Self.rangeText(expectedGames, expectedGamesLow, expectedGamesHigh, digits: 0)
    }

    /// A fan-legible durability label derived from the EB games-played rate — this is the SP-3
    /// availability signal in its season-grain, draft-relevant form.
    var durabilityBand: String {
        switch expectedGpRate {
        case 0.90...:      return "Iron"
        case 0.80..<0.90:  return "Durable"
        case 0.65..<0.80:  return "Some injury risk"
        default:           return "Fragile"
        }
    }
}

/// The single `fantasySeasonalValues/_meta` doc: season + count + asOf. Same defaulting pattern.
nonisolated struct FantasySeasonalMeta: Codable, Equatable, Hashable {
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
