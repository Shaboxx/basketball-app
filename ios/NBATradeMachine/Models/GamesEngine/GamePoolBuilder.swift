import Foundation

/// Freezes the app's live `Player` docs into game entities. Players outside the
/// five position codes are dropped (slot logic depends on them); a missing
/// impact rating enters at 0 — still pickable, just never CPU-favored.
nonisolated enum GamePoolBuilder {

    static let validPositions: Set<String> = ["PG", "SG", "SF", "PF", "C"]

    static func pool(from players: [Player]) -> [GameEntityRecord] {
        players.compactMap { p in
            guard validPositions.contains(p.position) else { return nil }
            return GameEntityRecord(id: p.slug,
                                    name: p.name,
                                    team: p.teamId,
                                    position: p.position,
                                    salary: p.salaryY1,
                                    rating: p.thetaBoard?.total ?? 0,
                                    offRating: p.thetaBoard?.off,
                                    defRating: p.thetaBoard?.def,
                                    minutes: p.relevance?.mpgSeason)
        }
    }
}
