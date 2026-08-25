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

    init(id: String, name: String, team: String, position: String,
         salary: Int?, rating: Double,
         offRating: Double? = nil, defRating: Double? = nil, minutes: Double? = nil) {
        self.id = id
        self.name = name
        self.team = team
        self.position = position
        self.salary = salary
        self.rating = rating
        self.offRating = offRating
        self.defRating = defRating
        self.minutes = minutes
    }
}

/// The constraint-addressable fields of an entity (spec §6). New data (awards,
/// decades, …) becomes new cases here — engines never change (spec §32).
nonisolated enum GameField: String, Codable, Equatable {
    case team, position, salary, rating
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
        }
    }
}
