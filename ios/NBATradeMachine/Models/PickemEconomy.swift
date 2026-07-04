import Foundation

/// Pure port of `scripts/pickem/scoring.py::coin_delta` — the settlement CF is the source of
/// truth, this mirrors it CLIENT-side only to preview winnings before a pick. Uses
/// `.toNearestOrEven` (banker's rounding) to match Python's `round()`, and rounds the free +
/// stake terms SEPARATELY (as the Python does), so previews equal the eventual settlement.
/// `nonisolated` for unit tests. Coins are virtual + non-cashable (floored at 0).
nonisolated enum PickemEconomy {
    static let welcomeCoins = 1000    // WELCOME_COINS
    static let baseUnit = 100         // BASE_UNIT
    static let freeLoss = 50          // FREE_LOSS

    /// Coins won/lost on a settled pick. `prob` = implied prob of the chosen side (0<prob<1).
    static func coinDelta(correct: Bool, prob: Double, stake: Int = 0) -> Int {
        guard prob > 0 else { return correct ? 0 : -freeLoss - stake }   // guard 1/0
        let d = 1.0 / prob
        if correct {
            let free  = Int((Double(baseUnit) * (d - 1.0)).rounded(.toNearestOrEven))
            let boost = Int((Double(stake) * (d - 1.0)).rounded(.toNearestOrEven))
            return free + boost
        }
        return -freeLoss - stake
    }

    /// Coins gained if this pick hits (for the card's upside preview).
    static func potentialWin(prob: Double, stake: Int) -> Int { coinDelta(correct: true, prob: prob, stake: stake) }
    /// Coins lost if this pick misses (for the card's downside preview).
    static func potentialLoss(stake: Int) -> Int { -freeLoss - stake }
    /// Balance after applying a delta (floored at 0, like the CF).
    static func projectedBalance(_ balance: Int, delta: Int) -> Int { max(0, balance + delta) }
}

/// Pure mirror of the `pickemPicks` create rules, so `PickemStore.submit` fails fast with a
/// typed, actionable reason before the network round-trip. The server re-checks everything
/// (balance is authoritative there), so this is UX only. `nonisolated` for unit tests.
nonisolated enum PickemPrecheck {
    enum Failure: Error, Equatable {
        case notSignedIn, alreadyPicked, questionNotOpen, questionLocked
        case sideNotValid, stakeNegative, stakeTooHigh
        /// The server rejected the write for a reason the client can't disambiguate (already
        /// picked / stale balance / lock race); the store re-syncs and reports this.
        case couldNotPlace

        /// User-facing copy.
        var message: String {
            switch self {
            case .notSignedIn:    return "Sign in with Apple to place a pick."
            case .alreadyPicked:  return "You've already picked this one."
            case .questionNotOpen: return "This question is closed."
            case .questionLocked: return "This question is locked — the game has started."
            case .sideNotValid:   return "Pick a valid side."
            case .stakeNegative:  return "Stake can't be negative."
            case .stakeTooHigh:   return "You don't have enough coins to stake that much."
            case .couldNotPlace:  return "Couldn't place that pick — we refreshed your coins, please try again."
            }
        }
    }

    /// The first failing rule, or nil if the pick is placeable. Order chosen so the most
    /// actionable message wins.
    static func validate(signedIn: Bool, question: PickemQuestion, side: String,
                         stake: Int, balance: Int, alreadyPicked: Bool, now: Date = Date()) -> Failure? {
        if !signedIn { return .notSignedIn }
        if alreadyPicked { return .alreadyPicked }
        if question.status != "open" { return .questionNotOpen }
        if now >= question.lockTime { return .questionLocked }
        if !question.sides.contains(side) { return .sideNotValid }
        if stake < 0 { return .stakeNegative }
        if stake > balance { return .stakeTooHigh }
        return nil
    }
}
