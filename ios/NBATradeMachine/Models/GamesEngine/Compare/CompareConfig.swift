import Foundation

/// A comparable per-player metric (spec §19). All are zero-async — already frozen
/// on `GameEntityRecord`. `value` is nil when the player lacks that metric.
nonisolated enum CompareMetric: String, Codable, Equatable {
    case overall, offense, defense, salary, minutes

    func value(_ e: GameEntityRecord) -> Double? {
        switch self {
        case .overall: return e.rating
        case .offense: return e.offRating
        case .defense: return e.defRating
        case .salary:  return e.salary.map(Double.init)
        case .minutes: return e.minutes
        }
    }

    var prompt: String {
        switch self {
        case .overall: return "Who's the better player?"
        case .offense: return "Who's the better scorer?"
        case .defense: return "Who's the better defender?"
        case .salary:  return "Who earns more?"
        case .minutes: return "Who plays more minutes?"
        }
    }

    /// The metric value formatted for display.
    func format(_ e: GameEntityRecord) -> String {
        switch self {
        case .salary:
            return "$\((e.salary ?? 0) / 1_000_000)M"
        case .minutes:
            return String(format: "%.1f mpg", e.minutes ?? 0)
        case .overall, .offense, .defense:
            return String(format: "%+.1f", value(e) ?? 0)
        }
    }
}

/// Higher or lower wins the round.
nonisolated enum CompareDirection: String, Codable, Equatable { case higher, lower }

nonisolated struct CompareConfig: Codable, Equatable {
    let metric: CompareMetric
    let direction: CompareDirection
}

/// A compare (Higher/Lower) game — self-contained.
nonisolated struct CompareDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let config: CompareConfig
}
