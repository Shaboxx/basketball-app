import Foundation

/// Pure CBA trade/roster rule engine. No Firestore, no SwiftUI, no `@MainActor`.
/// All thresholds are sourced from `leagueRules.json` (2025-26); the matching
/// formula tiers there are prose, so their numeric shapes live here, annotated.
enum TradeCompliance {

    // Roster (leagueRules.json::rosterRules.standardContractsRequired = "14 or 15")
    static let rosterMax = 15
    static let rosterMin = 14
    // Cash (leagueRules.json::tradeRules.cashLimit.perTeamPerYear)
    static let cashLimitPerTeam = 8_120_000
    // Matching (leagueRules.json::tradeRules.salaryMatching)
    static let matchBuffer = 250_000          // "+ $250,000"
    static let expandedTPECap = 7_936_000      // "capped at outgoing + $7,936,000"

    // MARK: §4.1 Roster
    static func rosterIssues(_ t: TeamContext) -> [ComplianceIssue] {
        if t.postTradeRosterCount > rosterMax {
            return [ComplianceIssue(
                severity: .block, category: .roster, teamId: t.teamId,
                message: "\(t.teamName): \(t.postTradeRosterCount) players after the trade — over the \(rosterMax)-man standard-roster maximum.")]
        }
        if t.postTradeRosterCount < rosterMin {
            let tail = t.isOffseason
                ? " (legal in the offseason, but must reach \(rosterMin) by opening night)."
                : "."
            return [ComplianceIssue(
                severity: .warn, category: .roster, teamId: t.teamId,
                message: "\(t.teamName): \(t.postTradeRosterCount) players after the trade — below the \(rosterMin)-man minimum\(tail)")]
        }
        return []
    }
}
