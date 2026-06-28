import Foundation

/// One CBA compliance finding produced by `TradeCompliance`. `.block` issues
/// make the trade invalid; `.warn` issues are advisory.
struct ComplianceIssue: Identifiable, Hashable {
    enum Severity: Hashable { case block, warn }
    enum Category: Hashable {
        case roster, stepien, salaryMatch, apron, maxSalary, cash, hardCap, signAndTrade
        case exceptionEligibility, draftPick, aggregation, waitingPeriod, tpe
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
    // --- Scaffolded (no data source yet; aggregation-timing/waiting-period checks
    // stay inert when these are nil). ---
    /// When this team acquired the player (for the 2-month no-aggregation window). (SG9)
    var acquiredDate: Date? = nil
    /// True if this is a minimum-salary contract (for the 3+-aggregation min-rule). (SG10)
    var isMinimumContract: Bool? = nil
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
    /// Same, BEFORE the trade — so Stepien only blocks gaps the trade CREATES, not
    /// pre-existing (often curated-data) gaps that are the team's standing position.
    let preTradeOwnedFirstRoundYears: Set<Int>
    /// Inclusive range of future draft years to evaluate Stepien gaps over.
    let draftYearHorizon: ClosedRange<Int>
    /// Dollar ceiling this team can't exceed this scenario (apron hard cap from an
    /// exception/sign-and-trade); nil = not hard-capped. (M2)
    let hardCapLimit: Int?
    /// True if this team is acquiring a player via sign-and-trade this scenario. (M3)
    let acquiringViaSignAndTrade: Bool
    /// Prior teams of the sign-and-trade players this team is ACQUIRING; each must be
    /// a participant in the trade. (M3)
    let signAndTradePriorTeamIds: [String]
    /// Every team participating in this trade (to check S&T prior-team participation).
    let tradeTeamIds: Set<String>
    /// Cap exceptions this team used for signings in this scenario. (SG2/SG4)
    let signedExceptions: [ExceptionType]
    /// Contract terms (years) of the sign-and-trade players this team is acquiring. (SG3)
    let signAndTradeAcquiredYears: [Int]
    /// Draft years of FIRST-round picks this team is SENDING out in the trade. (SG5)
    let conveyedFirstRoundYears: [Int]
    /// Draft years of ALL picks this team is sending out (round 1 + 2). (SG6)
    let conveyedPickYears: [Int]
    /// The next upcoming draft year (for the 7-years-out + frozen-pick windows). (SG5/SG6)
    let currentDraftYear: Int
    /// Total cash this team RECEIVES across the trade. (SG7)
    let cashReceived: Int
    // --- Scaffolded inputs (no data source yet; checks stay inert when absent) ---
    /// Two-way contract count after the trade (nil = unknown / no data). (SG8)
    let twoWayCount: Int?
    /// The scenario "as-of" date, for aggregation-timing + waiting-period windows. (SG9/SG10/SG12)
    let scenarioDate: Date?
    /// Standing traded-player exceptions (amounts) carried from prior trades. (SG11)
    let standingTPEs: [Int]
}
