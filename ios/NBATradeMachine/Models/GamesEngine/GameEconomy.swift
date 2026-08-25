import Foundation

/// How an entity is priced under a budget game (spec §11 subset). Both modes
/// ship; a preset picks one. `databaseValue` = real NBA salary (Fantasy Salary
/// Cap). `tierPrice` = a small 1…6 bucket from impact rating (the classic
/// "build a team for $15" feel), ready for a future all-time-team card.
nonisolated enum PricingMethod: String, Codable, Equatable {
    case databaseValue
    case tierPrice
}

/// A budget/economy modifier (spec §11). Optional on `GameDefinition`; absent =
/// no budget (Phase-1 behavior).
nonisolated struct EconomyConfig: Codable, Equatable {
    let pricingMethod: PricingMethod
    /// Units follow `pricingMethod`: dollars for `.databaseValue`, tier-points
    /// (1…6 scale) for `.tierPrice`. Never mix the two scales downstream.
    let startingBudget: Int

    /// Cost of one entity under this economy (never negative). Under
    /// `.databaseValue` a nil salary prices at 0 — i.e. a missing-salary player
    /// is treated as FREE by design; a preset that can't tolerate that should
    /// filter such entities out of its pool.
    func price(_ entity: GameEntityRecord) -> Int {
        switch pricingMethod {
        case .databaseValue:
            return max(0, entity.salary ?? 0)
        case .tierPrice:
            return Self.tier(forRating: entity.rating)
        }
    }

    /// Monotone-non-decreasing 1…6 bucketing of impact rating.
    static func tier(forRating r: Double) -> Int {
        switch r {
        case 6...:       return 6
        case 4..<6:      return 5
        case 2..<4:      return 4
        case 0..<2:      return 3
        case (-2)..<0:   return 2
        default:         return 1
        }
    }
}
