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

    // MARK: §4.3 Salary matching
    /// Max incoming aggregate salary the team may absorb, by post-trade tier.
    /// Sources (leagueRules.json::tradeRules.salaryMatching):
    /// - underCap: room + outgoing + $250k (the outgoing salaries also free cap space)
    /// - overCap/overTax (over cap, under first apron): expanded TPE — larger of
    ///   (200% + $250k, capped at outgoing + $7.936M) and (125% + $250k)
    /// - overFirstApron / overSecondApron: 100% + $0
    static func allowedIncoming(tier: LeagueRules.CapTier, outgoing: Int, capRoom: Int) -> Int {
        switch tier {
        case .underCap:
            // The team's OUTGOING salaries also free cap space, so it can absorb its
            // pre-trade room PLUS what it sends out, then the $250k allowance. (The
            // prior formula counted only pre-trade room and ignored outgoing, so it
            // wrongly blocked even-money trades for any team at or near the cap.)
            return max(capRoom, 0) + outgoing + matchBuffer
        case .overCap, .overTax:
            let formula1 = min(2 * outgoing + matchBuffer, outgoing + expandedTPECap)
            let formula2 = (outgoing * 125) / 100 + matchBuffer
            return max(formula1, formula2)
        case .overFirstApron, .overSecondApron:
            return outgoing
        }
    }

    static func salaryMatchIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard !t.outgoing.isEmpty, !t.incoming.isEmpty else { return [] }
        let outSum = t.outgoing.reduce(0) { $0 + $1.salaryY1 }
        let inSum = t.incoming.reduce(0) { $0 + $1.salaryY1 }
        let allowed = allowedIncoming(tier: t.postTradeTier, outgoing: outSum,
                                      capRoom: capRoomForUnderCap(t))
        guard inSum > allowed else { return [] }
        return [ComplianceIssue(
            severity: .block, category: .salaryMatch, teamId: t.teamId,
            message: "\(t.teamName): takes back \(dollars(inSum)) but its \(tierLabel(t.postTradeTier)) matching limit is \(dollars(allowed)).")]
    }

    /// Under-cap teams match into cap room; over-cap teams don't use room.
    /// `salaryCapFallback` is used only for this room estimate, never for apron
    /// decisions (those come from the real `LeagueRules` tier on the context).
    static func capRoomForUnderCap(_ t: TeamContext) -> Int {
        guard t.postTradeTier == .underCap else { return 0 }
        return max(0, salaryCapFallback - t.preTradeSalary)
    }

    // Cap used only for the under-cap room estimate; apron thresholds always come
    // from LeagueRules, never this constant. (leagueRules.json::systemLevels.salaryCap)
    static let salaryCapFallback = 154_647_000

    static func tierLabel(_ tier: LeagueRules.CapTier) -> String { tier.rawValue }

    static func dollars(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "$\(n)"
    }

    // MARK: §4.4 Apron restrictions
    static func apronIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard t.postTradeTier == .overSecondApron else { return [] }
        var issues: [ComplianceIssue] = []

        // No aggregation: heuristic — sends >=2 players AND takes back a single
        // contract larger than its largest single outgoing salary.
        if t.outgoing.count >= 2, let biggestOut = t.outgoing.map(\.salaryY1).max(),
           t.incoming.contains(where: { $0.salaryY1 > biggestOut }) {
            issues.append(ComplianceIssue(
                severity: .block, category: .apron, teamId: t.teamId,
                message: "\(t.teamName): second-apron teams cannot aggregate salaries — combining outgoing contracts to absorb a larger player is not allowed."))
        }
        // No cash sent.
        if t.cashSent > 0 {
            issues.append(ComplianceIssue(
                severity: .block, category: .apron, teamId: t.teamId,
                message: "\(t.teamName): second-apron teams cannot send cash in trades."))
        }
        // Frozen pick (advisory).
        issues.append(ComplianceIssue(
            severity: .warn, category: .apron, teamId: t.teamId,
            message: "\(t.teamName): while in the second apron, its first-round pick seven drafts out is frozen (moved to the end of the round)."))
        return issues
    }

    // MARK: §4.6 Cash limit
    static func cashIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard t.cashSent > cashLimitPerTeam else { return [] }
        return [ComplianceIssue(
            severity: .warn, category: .cash, teamId: t.teamId,
            message: "\(t.teamName): sending \(dollars(t.cashSent)) — over the \(dollars(cashLimitPerTeam)) per-team season cash limit.")]
    }

    // MARK: §4.2 Stepien rule
    static func stepienIssues(_ t: TeamContext) -> [ComplianceIssue] {
        var run = 0
        var gapStart = 0
        for year in t.draftYearHorizon {
            if t.ownedFirstRoundYears.contains(year) {
                run = 0
            } else {
                if run == 0 { gapStart = year }
                run += 1
                if run >= 2 {
                    return [ComplianceIssue(
                        severity: .block, category: .stepien, teamId: t.teamId,
                        message: "\(t.teamName): Stepien rule — no first-round pick in \(gapStart) and \(year). A team can't be without a first-round pick in consecutive drafts.")]
                }
            }
        }
        return []
    }

    // MARK: §4.5 Max-salary sanity
    static func maxSalaryIssues(_ t: TeamContext) -> [ComplianceIssue] {
        t.incoming.compactMap { c in
            guard let cap = c.standardMax ?? c.nextContractMax, c.salaryY1 > cap else { return nil }
            return ComplianceIssue(
                severity: .warn, category: .maxSalary, teamId: t.teamId,
                message: "\(t.teamName): incoming \(c.name) at \(dollars(c.salaryY1)) exceeds the \(dollars(cap)) max for their tier — check the contract data.")
        }
    }

    // MARK: §4.7 Hard cap (M2)
    static func hardCapIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard let limit = t.hardCapLimit, t.postTradeSalary > limit else { return [] }
        return [ComplianceIssue(
            severity: .block, category: .hardCap, teamId: t.teamId,
            message: "\(t.teamName): hard-capped at \(dollars(limit)) this season (an exception or sign-and-trade was used) — this move pushes salary to \(dollars(t.postTradeSalary)).")]
    }

    // MARK: §4.8 Sign-and-trade (M3)
    static func signAndTradeIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard t.acquiringViaSignAndTrade else { return [] }
        var issues: [ComplianceIssue] = []
        if t.postTradeTier == .overFirstApron || t.postTradeTier == .overSecondApron {
            issues.append(ComplianceIssue(
                severity: .block, category: .signAndTrade, teamId: t.teamId,
                message: "\(t.teamName): teams over the first apron cannot acquire a player via sign-and-trade."))
        }
        issues.append(ComplianceIssue(
            severity: .warn, category: .signAndTrade, teamId: t.teamId,
            message: "\(t.teamName): sign-and-trade requires a 3-4 year contract with the first year fully guaranteed, signed before opening night, and the prior team must be a trade participant. The acquirer is hard-capped at the first apron."))
        return issues
    }

    // MARK: aggregate
    static func evaluate(teams: [TeamContext]) -> [ComplianceIssue] {
        var issues: [ComplianceIssue] = []
        for t in teams {
            issues += rosterIssues(t)
            issues += stepienIssues(t)
            issues += salaryMatchIssues(t)
            issues += apronIssues(t)
            issues += maxSalaryIssues(t)
            issues += cashIssues(t)
            issues += hardCapIssues(t)
            issues += signAndTradeIssues(t)
        }
        return issues
    }
}
