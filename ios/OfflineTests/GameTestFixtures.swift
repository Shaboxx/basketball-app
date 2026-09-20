import Foundation
@testable import BasketballOffline

/// Shared builders for games-engine tests. `ent` defaults are deliberately
/// boring; tests override only what they assert on.
enum GameTestFixtures {
    static func ent(_ id: String, pos: String = "PG", team: String = "AAA",
                    rating: Double = 0, salary: Int? = nil) -> GameEntityRecord {
        GameEntityRecord(id: id, name: id.capitalized, team: team,
                         position: pos, salary: salary, rating: rating)
    }

    /// 10-man pool: two per position, teams AAA/BBB alternating, ratings 1...10.
    static func tenManPool() -> [GameEntityRecord] {
        let positions = ["PG", "SG", "SF", "PF", "C"]
        return (0..<10).map { i in
            ent("p\(i)", pos: positions[i % 5], team: i % 2 == 0 ? "AAA" : "BBB",
                rating: Double(i + 1), salary: (i + 1) * 1_000_000)
        }
    }
}
