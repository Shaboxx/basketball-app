import Foundation

/// One selectable entity in a game — Phase 1: a frozen snapshot of a current
/// NBA player. Game state never holds live `Player` references, so sessions are
/// self-contained, Codable, and testable without Firestore.
nonisolated struct GameEntityRecord: Identifiable, Codable, Equatable, Hashable {
    let id: String              // canonical player slug
    let name: String
    let team: String            // opaque team key (numeric NBA id in Phase 1); unique per team, used by uniqueBy(.team). NOT display-ready — resolve to a name for UI.
    let position: String        // "PG" | "SG" | "SF" | "PF" | "C"
    let salary: Int?            // current-year salary in dollars
    let rating: Double          // overall impact rating (CPU picks + TEAM_RATING scoring + classification order)
    // Phase-3 compare metrics — optional, additive. nil when unknown; a compare
    // game filters its pool to entities where its chosen metric is present.
    let offRating: Double?      // offensive impact
    let defRating: Double?      // defensive impact
    let minutes: Double?        // minutes per game (season)

    // Phase-4.5 historical fields — ADDITIVE + optional. Current-era (Phase-1)
    // entities never set these, so they decode/init as nil and the evaluator's
    // SQL-style missing-field semantics leave those games unchanged. A historical
    // entity fills them from the bundled dataset (see HistoricalPoolBuilder).
    let decadeStartYear: Int?   // 1990 / 2000 / 2010 / 2020
    let seasonStartYear: Int?   // e.g. 1996
    // Career accolades (counts; nil ⟺ unknown → never satisfies a ">=1" gate).
    let careerRings: Int?
    let careerMvp: Int?
    let careerFinalsMvp: Int?
    let careerAllNba: Int?
    let careerAllStar: Int?
    let careerAllDefense: Int?
    let draftYear: Int?
    let draftRound: Int?
    let draftPick: Int?
    // Key per-season stats (nil ⟺ absent in source).
    let pts: Double?
    let reb: Double?
    let ast: Double?
    let netRating: Double?

    // Phase-5 CONTENT fields — ADDITIVE + optional (default nil so every previously
    // encoded Phase-1..4.5 blob decodes unchanged). Populated from the historical
    // dataset by HistoricalPoolBuilder; current-era entities leave them nil, so
    // the evaluator's SQL-style missing-field semantics leave those games untouched.
    // These give GUESS clues / QUIZ superlatives / SURVIVOR predicates the richer
    // stat + label surface they need without a parallel content record type.
    let seasonLabel: String?    // "1996-97" — human season label (display + clue)
    let age: Double?            // player age that season
    let stl: Double?
    let blk: Double?
    let tov: Double?
    let fgPct: Double?
    let threePct: Double?       // ⚠️ legitimately 0.0 for many pre-2015 bigs (not missing)
    let ftPct: Double?
    let tsPct: Double?
    let usgPct: Double?
    let pie: Double?

    init(id: String, name: String, team: String, position: String,
         salary: Int?, rating: Double,
         offRating: Double? = nil, defRating: Double? = nil, minutes: Double? = nil,
         decadeStartYear: Int? = nil, seasonStartYear: Int? = nil,
         careerRings: Int? = nil, careerMvp: Int? = nil, careerFinalsMvp: Int? = nil,
         careerAllNba: Int? = nil, careerAllStar: Int? = nil, careerAllDefense: Int? = nil,
         draftYear: Int? = nil, draftRound: Int? = nil, draftPick: Int? = nil,
         pts: Double? = nil, reb: Double? = nil, ast: Double? = nil,
         netRating: Double? = nil,
         seasonLabel: String? = nil, age: Double? = nil,
         stl: Double? = nil, blk: Double? = nil, tov: Double? = nil,
         fgPct: Double? = nil, threePct: Double? = nil, ftPct: Double? = nil,
         tsPct: Double? = nil, usgPct: Double? = nil, pie: Double? = nil) {
        self.id = id
        self.name = name
        self.team = team
        self.position = position
        self.salary = salary
        self.rating = rating
        self.offRating = offRating
        self.defRating = defRating
        self.minutes = minutes
        self.decadeStartYear = decadeStartYear
        self.seasonStartYear = seasonStartYear
        self.careerRings = careerRings
        self.careerMvp = careerMvp
        self.careerFinalsMvp = careerFinalsMvp
        self.careerAllNba = careerAllNba
        self.careerAllStar = careerAllStar
        self.careerAllDefense = careerAllDefense
        self.draftYear = draftYear
        self.draftRound = draftRound
        self.draftPick = draftPick
        self.pts = pts
        self.reb = reb
        self.ast = ast
        self.netRating = netRating
        self.seasonLabel = seasonLabel
        self.age = age
        self.stl = stl
        self.blk = blk
        self.tov = tov
        self.fgPct = fgPct
        self.threePct = threePct
        self.ftPct = ftPct
        self.tsPct = tsPct
        self.usgPct = usgPct
        self.pie = pie
    }
}

/// The constraint-addressable fields of an entity (spec §6). New data (awards,
/// decades, …) becomes new cases here — engines never change (spec §32).
/// The Phase-4.5 cases resolve to `nil` on current-era entities (they don't
/// carry those fields), so a constraint on one silently excludes current
/// players — which is exactly what a historical-pool constraint wants.
nonisolated enum GameField: String, Codable, Equatable {
    case team, position, salary, rating
    // Phase-4.5 historical fields (all optional on the record).
    case decadeStartYear, seasonStartYear
    case careerRings, careerMvp, careerFinalsMvp, careerAllNba, careerAllStar, careerAllDefense
    case draftYear, draftRound, draftPick
    case pts, reb, ast, netRating
    // Phase-5 content fields (all optional on the record).
    case seasonLabel, age
    case stl, blk, tov, fgPct, threePct, ftPct, tsPct, usgPct, pie
}

/// A typed field value; constraints compare like against like.
nonisolated enum GameFieldValue: Equatable {
    case string(String)
    case number(Double)
}

nonisolated extension GameEntityRecord {
    func value(for field: GameField) -> GameFieldValue? {
        switch field {
        case .team:     return .string(team)
        case .position: return .string(position)
        case .salary:   return salary.map { .number(Double($0)) }
        case .rating:   return .number(rating)
        // Phase-4.5: nil ⟹ absent field ⟹ evaluator's missing-field semantics.
        case .decadeStartYear: return decadeStartYear.map { .number(Double($0)) }
        case .seasonStartYear: return seasonStartYear.map { .number(Double($0)) }
        case .careerRings:      return careerRings.map { .number(Double($0)) }
        case .careerMvp:        return careerMvp.map { .number(Double($0)) }
        case .careerFinalsMvp:  return careerFinalsMvp.map { .number(Double($0)) }
        case .careerAllNba:     return careerAllNba.map { .number(Double($0)) }
        case .careerAllStar:    return careerAllStar.map { .number(Double($0)) }
        case .careerAllDefense: return careerAllDefense.map { .number(Double($0)) }
        case .draftYear:        return draftYear.map { .number(Double($0)) }
        case .draftRound:       return draftRound.map { .number(Double($0)) }
        case .draftPick:        return draftPick.map { .number(Double($0)) }
        case .pts:              return pts.map { .number($0) }
        case .reb:              return reb.map { .number($0) }
        case .ast:              return ast.map { .number($0) }
        case .netRating:        return netRating.map { .number($0) }
        // Phase-5 content fields.
        case .seasonLabel:      return seasonLabel.map { .string($0) }
        case .age:              return age.map { .number($0) }
        case .stl:              return stl.map { .number($0) }
        case .blk:              return blk.map { .number($0) }
        case .tov:              return tov.map { .number($0) }
        case .fgPct:            return fgPct.map { .number($0) }
        case .threePct:         return threePct.map { .number($0) }
        case .ftPct:            return ftPct.map { .number($0) }
        case .tsPct:            return tsPct.map { .number($0) }
        case .usgPct:           return usgPct.map { .number($0) }
        case .pie:              return pie.map { .number($0) }
        }
    }
}
