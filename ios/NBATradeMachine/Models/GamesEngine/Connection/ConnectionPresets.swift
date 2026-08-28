import Foundation

/// How a completed chain is scored relative to the graph's shortest path.
nonisolated enum ConnectionScoreMode: String, Codable, Equatable {
    /// Reward SHORTER chains (Sol Q4): a chain matching the optimal length scores
    /// max; each extra link past optimal deducts.
    case optimality
}

/// A CONNECTION preset — presets-as-data. `targetDistanceMin/Max` bound the seeded
/// endpoint distance (in edges) so the puzzle is neither trivial (distance 1) nor
/// unwieldy. `id` == registry card id.
nonisolated struct ConnectionDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let targetDistanceMin: Int
    let targetDistanceMax: Int
    let scoreMode: ConnectionScoreMode

    init(id: String, title: String, targetDistanceMin: Int = 2,
         targetDistanceMax: Int = 4, scoreMode: ConnectionScoreMode = .optimality) {
        self.id = id
        self.title = title
        self.targetDistanceMin = targetDistanceMin
        self.targetDistanceMax = targetDistanceMax
        self.scoreMode = scoreMode
    }
}

nonisolated enum ConnectionPresets {

    static let sixDegreesId = "six-degrees"

    static func definition(for gameId: String) -> ConnectionDefinition? {
        switch gameId {
        case Self.sixDegreesId: return sixDegrees
        default:                return nil
        }
    }

    /// Link two seeded endpoints via a teammate chain — reward shorter.
    static var sixDegrees: ConnectionDefinition {
        ConnectionDefinition(id: Self.sixDegreesId, title: "Six Degrees",
                             targetDistanceMin: 2, targetDistanceMax: 4)
    }
}
