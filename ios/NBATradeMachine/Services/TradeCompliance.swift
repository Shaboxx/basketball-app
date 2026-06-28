import Foundation

/// Pure CBA trade/roster rule engine. No Firestore, no SwiftUI, no `@MainActor`.
/// All thresholds are sourced from `leagueRules.json` (2025-26); the matching
/// formula tiers there are prose, so their numeric shapes live here, annotated.
enum TradeCompliance {

    // Roster (leagueRules.json::rosterRules.standardContractsRequired = "14 or 15")
    static let rosterMax = 15
    static let rosterMin = 14
    // Offseason/camp roster ceiling (leagueRules.json::rosterRules.offseasonAndCampMax)
    static let offseasonRosterMax = 21
    // Cash (leagueRules.json::tradeRules.cashLimit.perTeamPerYear)
    static let cashLimitPerTeam = 8_120_000
    // Matching (leagueRules.json::tradeRules.salaryMatching)
    static let matchBuffer = 250_000          // "+ $250,000"
    static let expandedTPECap = 7_936_000      // "capped at outgoing + $7,936,000"

    // MARK: §4.1 Roster
    static func rosterIssues(_ t: TeamContext) -> [ComplianceIssue] {
        let n = t.postTradeRosterCount
        if t.isOffseason {
            // Offseason/camp rosters may carry up to 21; landing at 16–21 is legal
            // now but must be trimmed to the 15-man cap by opening night.
            if n > offseasonRosterMax {
                return [ComplianceIssue(
                    severity: .block, category: .roster, teamId: t.teamId,
                    message: "\(t.teamName): \(n) players after the trade — over the \(offseasonRosterMax)-man offseason/camp maximum.")]
            }
            if n > rosterMax {
                return [ComplianceIssue(
                    severity: .warn, category: .roster, teamId: t.teamId,
                    message: "\(t.teamName): \(n) players after the trade — legal in the offseason, but must reach \(rosterMax) by opening night.")]
            }
        } else if n > rosterMax {
            return [ComplianceIssue(
                severity: .block, category: .roster, teamId: t.teamId,
                message: "\(t.teamName): \(n) players after the trade — over the \(rosterMax)-man standard-roster maximum.")]
        }
        if n < rosterMin {
            let tail = t.isOffseason
                ? " (legal in the offseason, but must reach \(rosterMin) by opening night)."
                : "."
            return [ComplianceIssue(
                severity: .warn, category: .roster, teamId: t.teamId,
                message: "\(t.teamName): \(n) players after the trade — below the \(rosterMin)-man minimum\(tail)")]
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
        // Only the RECEIVING side needs matching. A team with no incoming has nothing
        // to match (it's dumping salary). A one-way receiver (no outgoing) is matched
        // against its cap room (under-cap) or 100%/TPE band — outSum=0 falls through
        // allowedIncoming correctly (under-cap -> room+$250k; over-cap -> $250k, i.e. it
        // can't absorb a real contract without a traded-player exception).
        guard !t.incoming.isEmpty else { return [] }
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

        // No aggregation: a second-apron team can only use single-player traded-player
        // exceptions (100% + $0), so every incoming salary must fit into ONE outgoing
        // player's slot — i.e. the incoming set must be assignable to the outgoing
        // players with each outgoing "bucket" summing to <= that player's salary. If no
        // such assignment exists, absorbing the incoming requires AGGREGATING outgoing
        // salaries, which is banned. (Only meaningful when sending >=2 players; a single
        // outgoing can't be aggregated and over-match is already caught by salary matching.)
        if t.outgoing.count >= 2,
           !canMatchWithoutAggregation(incoming: t.incoming.map(\.salaryY1),
                                       outgoing: t.outgoing.map(\.salaryY1)) {
            issues.append(ComplianceIssue(
                severity: .block, category: .apron, teamId: t.teamId,
                message: "\(t.teamName): second-apron teams cannot aggregate salaries — the incoming players can't be matched without combining outgoing contracts."))
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

    /// Can `incoming` salaries be absorbed WITHOUT aggregating `outgoing` salaries? —
    /// assign every incoming to a single outgoing "bucket" so each bucket's total stays
    /// <= that outgoing player's salary (multiple incoming may share one bucket; no
    /// incoming may span two). Exact backtracking; trade sizes are tiny.
    static func canMatchWithoutAggregation(incoming: [Int], outgoing: [Int]) -> Bool {
        let items = incoming.filter { $0 > 0 }.sorted(by: >)   // largest first prunes fastest
        if items.isEmpty { return true }
        if outgoing.isEmpty { return false }
        var capacity = outgoing
        func place(_ i: Int) -> Bool {
            if i == items.count { return true }
            let item = items[i]
            var tried = Set<Int>()
            for b in capacity.indices where capacity[b] >= item && !tried.contains(capacity[b]) {
                tried.insert(capacity[b])   // symmetry break: skip buckets with identical remaining capacity
                capacity[b] -= item
                if place(i + 1) { return true }
                capacity[b] += item
            }
            return false
        }
        return place(0)
    }

    // MARK: §4.6 Cash limit
    static func cashIssues(_ t: TeamContext) -> [ComplianceIssue] {
        // The per-team annual cash limit is a HARD ceiling (2023 CBA Art. VII), tracked
        // separately for cash SENT and RECEIVED (not netted) — no exception permits
        // exceeding it on either side, so these are blocks.
        var issues: [ComplianceIssue] = []
        if t.cashSent > cashLimitPerTeam {
            issues.append(ComplianceIssue(
                severity: .block, category: .cash, teamId: t.teamId,
                message: "\(t.teamName): sending \(dollars(t.cashSent)) — over the \(dollars(cashLimitPerTeam)) per-team season cash limit."))
        }
        // SG7: receiving over the limit is equally illegal (a 3+-team trade can route
        // cash from several senders to one team).
        if t.cashReceived > cashLimitPerTeam {
            issues.append(ComplianceIssue(
                severity: .block, category: .cash, teamId: t.teamId,
                message: "\(t.teamName): receiving \(dollars(t.cashReceived)) — over the \(dollars(cashLimitPerTeam)) per-team season cash limit."))
        }
        return issues
    }

    // SG2 (exception eligibility by apron) is ENFORCED by hardCapIssues: using an
    // NTMLE/BAE hard-caps the team at the first apron and the taxpayer MLE at the second,
    // so an over-apron team using an ineligible exception already trips the hard cap
    // (strict-over, no at-apron false-positive). A separate eligibility block was
    // redundant with it and fired one dollar early at exactly the apron, so it was
    // removed. (A clearer per-exception message + UI Picker filtering by tier is a
    // deferred UI improvement — `signedExceptions` is carried for that.)

    // MARK: §4.2b Draft-pick trade limits (SG5/SG6)
    static let pickTradeHorizonYears = 7
    static func draftPickIssues(_ t: TeamContext) -> [ComplianceIssue] {
        var issues: [ComplianceIssue] = []
        let maxYear = t.currentDraftYear + pickTradeHorizonYears
        // SG6: only picks within 7 drafts of the next draft may be traded.
        for y in Set(t.conveyedPickYears).sorted() where y > maxYear {
            issues.append(ComplianceIssue(
                severity: .block, category: .draftPick, teamId: t.teamId,
                message: "\(t.teamName): can't trade a \(y) pick — only picks through \(maxYear) (7 drafts out) may be traded."))
        }
        // SG5: a second-apron team's first-round pick 7 drafts out is frozen (untradeable).
        if t.postTradeTier == .overSecondApron, t.conveyedFirstRoundYears.contains(maxYear) {
            issues.append(ComplianceIssue(
                severity: .block, category: .draftPick, teamId: t.teamId,
                message: "\(t.teamName): second-apron teams can't trade their \(maxYear) first-round pick — it's frozen."))
        }
        return issues
    }

    // MARK: scaffolded checks (inert until a data source populates the inputs)
    static let twoWayMax = 3   // leagueRules.json::rosterRules.twoWayContractsAllowed

    /// SG8 — two-way contract count. Inert when `twoWayCount` is nil (no data).
    static func twoWayIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard let n = t.twoWayCount, n > twoWayMax else { return [] }
        return [ComplianceIssue(
            severity: .block, category: .roster, teamId: t.teamId,
            message: "\(t.teamName): \(n) two-way contracts after the trade — over the \(twoWayMax) allowed.")]
    }

    /// SG9/SG10 — aggregation timing. Inert without a scenario date / acquisition dates.
    static func aggregationTimingIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard let asOf = t.scenarioDate, t.outgoing.count >= 2 else { return [] }
        var issues: [ComplianceIssue] = []
        // SG9: a player acquired < 2 months ago can't be aggregated with others.
        for c in t.outgoing {
            if let acq = c.acquiredDate, daysBetween(acq, asOf) < 60 {
                issues.append(ComplianceIssue(
                    severity: .block, category: .aggregation, teamId: t.teamId,
                    message: "\(t.teamName): \(c.name) was acquired less than 2 months ago and can't be aggregated in a trade yet."))
            }
        }
        // SG10: when aggregating 3+ players, only one may be on a minimum contract.
        if t.outgoing.count >= 3 {
            let mins = t.outgoing.filter { $0.isMinimumContract == true }.count
            if mins > 1 {
                issues.append(ComplianceIssue(
                    severity: .block, category: .aggregation, teamId: t.teamId,
                    message: "\(t.teamName): when aggregating 3+ players, only one may be on a minimum-salary contract (\(mins) here)."))
            }
        }
        return issues
    }

    /// SG11 — prior-year traded-player exceptions. A second-apron team can't use a TPE
    /// generated in a prior year. Inert until standing TPEs are modeled (always empty).
    static func tpeIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard t.postTradeTier == .overSecondApron, !t.standingTPEs.isEmpty,
              t.outgoing.isEmpty, !t.incoming.isEmpty else { return [] }
        return [ComplianceIssue(
            severity: .block, category: .tpe, teamId: t.teamId,
            message: "\(t.teamName): second-apron teams can't use a traded-player exception generated in a prior year.")]
    }

    /// SG12 — post-acquisition trade waiting periods. Inert without acquisition/signing
    /// dates + a scenario date; uses acquiredDate as the proxy for the restriction window.
    static func waitingPeriodIssues(_ t: TeamContext) -> [ComplianceIssue] {
        guard let asOf = t.scenarioDate else { return [] }
        return t.outgoing.compactMap { c in
            guard let acq = c.acquiredDate, daysBetween(acq, asOf) < 60 else { return nil }
            return ComplianceIssue(
                severity: .warn, category: .waitingPeriod, teamId: t.teamId,
                message: "\(t.teamName): \(c.name) may still be inside a post-acquisition trade-restriction window.")
        }
    }

    private static func daysBetween(_ a: Date, _ b: Date) -> Int {
        Int(b.timeIntervalSince(a) / 86_400)
    }

    // MARK: §4.2 Stepien rule
    static func stepienIssues(_ t: TeamContext) -> [ComplianceIssue] {
        // Only block a consecutive-draft gap the TRADE CREATES. A team's pre-trade
        // pick position is CBA-legal by definition (and curated pick data is often
        // incomplete), so a gap present both before and after — or a pick-less trade
        // (identical owned sets) — must not block.
        let before = stepienGapStarts(owned: t.preTradeOwnedFirstRoundYears, horizon: t.draftYearHorizon)
        let after = stepienGapStarts(owned: t.ownedFirstRoundYears, horizon: t.draftYearHorizon)
        guard let created = after.subtracting(before).min() else { return [] }
        return [ComplianceIssue(
            severity: .block, category: .stepien, teamId: t.teamId,
            message: "\(t.teamName): Stepien rule — this trade leaves no first-round pick in \(created) and \(created + 1). A team can't be without a first-round pick in consecutive drafts.")]
    }

    /// Start years of consecutive-draft gaps: each `y` where the team owns NO
    /// first-rounder in both `y` and `y+1` within the horizon.
    private static func stepienGapStarts(owned: Set<Int>, horizon: ClosedRange<Int>) -> Set<Int> {
        guard horizon.lowerBound < horizon.upperBound else { return [] }
        var starts = Set<Int>()
        for y in horizon.lowerBound..<horizon.upperBound where !owned.contains(y) && !owned.contains(y + 1) {
            starts.insert(y)
        }
        return starts
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
        // The signed player's prior (Bird-rights) team must sign AND simultaneously
        // trade them — i.e. be a participant in this trade.
        if t.signAndTradePriorTeamIds.contains(where: { !t.tradeTeamIds.contains($0) }) {
            issues.append(ComplianceIssue(
                severity: .block, category: .signAndTrade, teamId: t.teamId,
                message: "\(t.teamName): a sign-and-trade requires the player's prior team to be a participant in the trade."))
        }
        // SG3: a sign-and-trade contract must be 3-4 years.
        for yrs in t.signAndTradeAcquiredYears where yrs < 3 || yrs > 4 {
            issues.append(ComplianceIssue(
                severity: .block, category: .signAndTrade, teamId: t.teamId,
                message: "\(t.teamName): a sign-and-trade contract must be 3 to 4 years (this one is \(yrs))."))
        }
        // SG4: a sign-and-trade can't be combined with the Non-Taxpayer MLE, Room MLE,
        // or Bi-Annual exception in the same offseason.
        let stConflicts: Set<ExceptionType> = [.nonTaxpayerMLE, .roomMLE, .biAnnual]
        if t.signedExceptions.contains(where: { stConflicts.contains($0) }) {
            issues.append(ComplianceIssue(
                severity: .block, category: .signAndTrade, teamId: t.teamId,
                message: "\(t.teamName): a sign-and-trade can't be combined with the Non-Taxpayer MLE, Room MLE, or Bi-Annual exception."))
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
            issues += draftPickIssues(t)              // SG5/SG6
            issues += twoWayIssues(t)                 // SG8 (scaffold)
            issues += aggregationTimingIssues(t)      // SG9/SG10 (scaffold)
            issues += tpeIssues(t)                    // SG11 (scaffold)
            issues += waitingPeriodIssues(t)          // SG12 (scaffold)
        }
        return issues
    }
}
