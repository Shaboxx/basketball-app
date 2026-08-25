import Foundation

/// One selectable entity in a game — Phase 1: a frozen snapshot of a current
/// NBA player. Game state never holds live `Player` references, so sessions are
/// self-contained, Codable, and testable without Firestore.
nonisolated struct GameEntityRecord: Identifiable, Codable, Equatable, Hashable {
    let id: String              // canonical player slug
    let name: String
    let team: String            // team tricode, e.g. "DEN"
    let position: String        // "PG" | "SG" | "SF" | "PF" | "C"
    let salary: Int?            // current-year salary in dollars
    let rating: Double          // impact rating (CPU picks + TEAM_RATING scoring)
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

extension GameEntityRecord {
    func value(for field: GameField) -> GameFieldValue? {
        switch field {
        case .team:     return .string(team)
        case .position: return .string(position)
        case .salary:   return salary.map { .number(Double($0)) }
        case .rating:   return .number(rating)
        }
    }
}
