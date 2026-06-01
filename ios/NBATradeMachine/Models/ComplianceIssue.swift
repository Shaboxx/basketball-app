import Foundation

/// One CBA compliance finding produced by `TradeCompliance`. `.block` issues
/// make the trade invalid; `.warn` issues are advisory.
struct ComplianceIssue: Identifiable, Hashable {
    enum Severity: Hashable { case block, warn }
    enum Category: Hashable {
        case roster, stepien, salaryMatch, apron, maxSalary, cash, hardCap
    }
    let id = UUID()
    let severity: Severity
    let category: Category
    let teamId: String
    let message: String
}

/// Minimal contract view used by the pure rule engine. Decoupled from `Player`
/// so the engine has no Firestore/SwiftUI dependency and is fully testable.
struct ContractLite: Hashable {
    let playerId: String
    let name: String
    let salaryY1: Int
    let standardMax: Int?
    let nextContractMax: Int?
}

/// Everything `TradeCompliance` needs about one team in a proposed trade.
/// Assembled by `TradeMachineViewModel`; all salary figures are this-year cash.
struct TeamContext {
    let teamId: String
    let teamName: String
    let preTradeSalary: Int
    let postTradeSalary: Int
    let postTradeTier: LeagueRules.CapTier
    let incoming: [ContractLite]
    let outgoing: [ContractLite]
    let cashSent: Int
    let postTradeRosterCount: Int
    let isOffseason: Bool
    /// Future draft years in which the team owns >=1 first-round pick AFTER the
    /// trade (protected picks and swaps count as owned).
    let ownedFirstRoundYears: Set<Int>
    /// Inclusive range of future draft years to evaluate Stepien gaps over.
    let draftYearHorizon: ClosedRange<Int>
    /// Dollar ceiling this team can't exceed this scenario (first-apron hard
    /// cap from an exception/sign-and-trade); nil = not hard-capped. (M2)
    let hardCapLimit: Int?
}
