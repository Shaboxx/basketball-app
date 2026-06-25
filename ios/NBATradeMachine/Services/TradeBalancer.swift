import Foundation

/// Pure, deterministic 2-team trade balancer. No SwiftUI, no Firestore, no
/// `@MainActor` — same ethos as `TradeCompliance`. Driven entirely by injected
/// candidates + a legality oracle, so it unit-tests against synthetic data.
enum TradeBalancer {

    // MARK: - Inputs

    struct BalanceCandidate: Equatable {
        enum Kind: Equatable { case player(id: String); case pick(id: String) }
        let kind: Kind
        let ownerTeamId: String
        let salary: Int
        let valueToOtherTeam: Double
        let label: String

        var isPlayer: Bool { if case .player = kind { return true }; return false }
    }

    struct BalanceMove: Equatable {
        let candidate: BalanceCandidate
        let toTeamId: String
    }

    struct BalanceTolerance: Equatable {
        let floorDollars: Int
        let fraction: Double
        static let `default` = BalanceTolerance(floorDollars: 4_000_000, fraction: 0.10)
        func band(forLargerHaul haul: Double) -> Double {
            max(Double(floorDollars), haul * fraction)
        }
    }

    struct BalanceOptions {
        var includePicks: Bool = true
        var tolerance: BalanceTolerance = .default
        var branchFactor: Int = 3          // alternatives explored per search node
        var maxAdditions: Int = 8          // legalize search depth cap
        var escalationMaxPool: Int = 0     // 0 disables the Approach-2 hook (MVP)
    }

    struct BalanceInput {
        let teamAId: String
        let teamBId: String
        let baselineHaul: [String: Double]
        let candidatesA: [BalanceCandidate]
        let candidatesB: [BalanceCandidate]
        let options: BalanceOptions
    }

    // MARK: - Oracle

    struct LegalitySnapshot: Equatable {
        struct TeamSalary: Equatable {
            let allowedIncoming: Int
            let actualIncoming: Int
            let actualOutgoing: Int
            let rosterCount: Int
        }
        let blockingIssues: [String]
        let perTeam: [String: TeamSalary]

        var isLegal: Bool { blockingIssues.isEmpty }
        /// Total dollars the trade is over the matching ceiling, across teams.
        var salaryOvershoot: Int {
            perTeam.values.reduce(0) { $0 + max(0, $1.actualIncoming - $1.allowedIncoming) }
        }
        /// Total roster slots over the 15-man max, across teams.
        var rosterOver: Int {
            perTeam.values.reduce(0) { $0 + max(0, $1.rosterCount - 15) }
        }
    }

    typealias LegalityOracle = (_ moves: [BalanceMove]) -> LegalitySnapshot

    // MARK: - Output

    struct BalanceAddition: Equatable {
        enum Reason: Equatable { case salaryMatch, rosterCount, fairness, legal }
        let move: BalanceMove
        let reason: Reason
        let detail: String
    }

    enum BalanceOutcome: Equatable {
        case alreadyBalanced, balanced, legalizedButGapRemains, couldNotLegalize
    }

    struct BalanceResult: Equatable {
        let additions: [BalanceAddition]
        let outcome: BalanceOutcome
        let beforeLegal: Bool
        let afterLegal: Bool
        let beforeGap: Double
        let afterGap: Double
    }

    // MARK: - Helpers

    static func key(_ c: BalanceCandidate) -> String {
        switch c.kind {
        case .player(let id): return "p:" + id
        case .pick(let id):   return "k:" + id
        }
    }

    static func other(of teamId: String, _ input: BalanceInput) -> String {
        teamId == input.teamAId ? input.teamBId : input.teamAId
    }

    static func haul(_ additions: [BalanceAddition], _ input: BalanceInput) -> [String: Double] {
        var h = input.baselineHaul
        h[input.teamAId, default: 0] += 0
        h[input.teamBId, default: 0] += 0
        for a in additions {
            h[a.move.toTeamId, default: 0] += a.move.candidate.valueToOtherTeam
        }
        return h
    }

    static func gap(_ additions: [BalanceAddition], _ input: BalanceInput) -> Double {
        let h = haul(additions, input)
        return (h[input.teamAId] ?? 0) - (h[input.teamBId] ?? 0)
    }

    // MARK: - Entry

    static func balance(_ input: BalanceInput, legality: LegalityOracle) -> BalanceResult {
        let before = legality([])
        let beforeGap = gap([], input)
        var additions: [BalanceAddition] = []

        let legalized = legalize(input: input, legality: legality, into: &additions)
        let afterLegalSnap = legality(additions.map(\.move))

        if !legalized {
            let escalated = escalateIfEligible(input: input, legality: legality, additions: additions)
            return escalated ?? BalanceResult(
                additions: additions,
                outcome: .couldNotLegalize,
                beforeLegal: before.isLegal,
                afterLegal: afterLegalSnap.isLegal,
                beforeGap: beforeGap,
                afterGap: gap(additions, input))
        }

        balanceFairness(input: input, legality: legality, into: &additions)

        let finalSnap = legality(additions.map(\.move))
        let finalGap = gap(additions, input)
        let h = haul(additions, input)
        let band = input.options.tolerance.band(forLargerHaul: max(h[input.teamAId] ?? 0, h[input.teamBId] ?? 0))

        let outcome: BalanceOutcome
        if abs(finalGap) <= band {
            // Within tolerance: nothing added means it was already fair, otherwise
            // the additions made it fair.
            outcome = additions.isEmpty ? .alreadyBalanced : .balanced
        } else {
            // Legal (Phase A succeeded) but the value gap couldn't be closed from
            // these rosters — whether or not any additions were made.
            outcome = .legalizedButGapRemains
        }

        return BalanceResult(
            additions: additions,
            outcome: outcome,
            beforeLegal: before.isLegal,
            afterLegal: finalSnap.isLegal,
            beforeGap: beforeGap,
            afterGap: finalGap)
    }

    // MARK: - Phase A: legalize (bounded best-first search)

    private static func objective(_ s: LegalitySnapshot) -> (Int, Int, Int) {
        (s.blockingIssues.count, s.salaryOvershoot, s.rosterOver)
    }

    private static func less(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
        if a.0 != b.0 { return a.0 < b.0 }
        if a.1 != b.1 { return a.1 < b.1 }
        return a.2 < b.2
    }

    private static func legalize(input: BalanceInput, legality: LegalityOracle,
                                 into additions: inout [BalanceAddition]) -> Bool {
        let prefix = additions.map(\.move)
        let used = Set(additions.map { key($0.move.candidate) })
        guard let newMoves = dfsLegalize(prefix: prefix, input: input, legality: legality,
                                         used: used, depth: input.options.maxAdditions)
        else { return false }
        // Replay the found moves, categorizing each by what it improved.
        var running = prefix
        for mv in newMoves {
            let before = legality(running)
            let after = legality(running + [mv])
            let reason: BalanceAddition.Reason
            if after.salaryOvershoot < before.salaryOvershoot {
                reason = .salaryMatch
            } else if after.rosterOver < before.rosterOver {
                reason = .rosterCount
            } else {
                reason = .legal
            }
            additions.append(BalanceAddition(move: mv, reason: reason, detail: legalDetail(mv, reason)))
            running.append(mv)
        }
        return true
    }

    /// Returns the list of *new* moves that legalize the trade, or nil.
    private static func dfsLegalize(prefix: [BalanceMove], input: BalanceInput,
                                    legality: LegalityOracle, used: Set<String>,
                                    depth: Int) -> [BalanceMove]? {
        let snap = legality(prefix)
        if snap.isLegal { return [] }
        guard depth > 0 else { return nil }
        let current = objective(snap)

        // Rank player candidates (picks have salary 0 -> never fix salary blocks)
        // that strictly improve the objective; explore the best `branchFactor`.
        let ranked = (input.candidatesA + input.candidatesB)
            .filter { $0.isPlayer && !used.contains(key($0)) }
            .map { c -> (BalanceCandidate, (Int, Int, Int)) in
                let mv = BalanceMove(candidate: c, toTeamId: other(of: c.ownerTeamId, input))
                return (c, objective(legality(prefix + [mv])))
            }
            .filter { less($0.1, current) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return less(lhs.1, rhs.1) }                 // best improvement first
                if lhs.0.valueToOtherTeam != rhs.0.valueToOtherTeam {
                    return lhs.0.valueToOtherTeam < rhs.0.valueToOtherTeam       // ship least value
                }
                return lhs.0.salary < rhs.0.salary
            }
            .prefix(input.options.branchFactor)

        for (c, _) in ranked {
            let mv = BalanceMove(candidate: c, toTeamId: other(of: c.ownerTeamId, input))
            if let rest = dfsLegalize(prefix: prefix + [mv], input: input, legality: legality,
                                      used: used.union([key(c)]), depth: depth - 1) {
                return [mv] + rest
            }
        }
        return nil
    }

    private static func legalDetail(_ mv: BalanceMove, _ reason: BalanceAddition.Reason) -> String {
        switch reason {
        case .salaryMatch: return "\(mv.candidate.label) — sent to meet the salary-matching rule."
        case .rosterCount: return "\(mv.candidate.label) — sent to get under the 15-man roster limit."
        default:           return "\(mv.candidate.label) — sent to make the trade legal."
        }
    }

    // MARK: - Phase B: fairness

    private static func balanceFairness(input: BalanceInput, legality: LegalityOracle,
                                        into additions: inout [BalanceAddition]) {
        while true {
            let h = haul(additions, input)
            let hA = h[input.teamAId] ?? 0, hB = h[input.teamBId] ?? 0
            let g = hA - hB
            let band = input.options.tolerance.band(forLargerHaul: max(hA, hB))
            if abs(g) <= band { return }

            // Short-changed team = the one with the smaller haul; the OTHER team
            // (the donor) sends it an asset.
            let shortTeam = g > 0 ? input.teamBId : input.teamAId
            let donorCands = (shortTeam == input.teamAId) ? input.candidatesB : input.candidatesA
            let used = Set(additions.map { key($0.move.candidate) })
            let prefix = additions.map(\.move)

            var best: (cand: BalanceCandidate, residual: Double)?
            for c in donorCands where !used.contains(key(c)) {
                if !input.options.includePicks && !c.isPlayer { continue }
                let mv = BalanceMove(candidate: c, toTeamId: shortTeam)
                guard legality(prefix + [mv]).isLegal else { continue }       // must not break legality
                let v = c.valueToOtherTeam
                let newG = (shortTeam == input.teamAId) ? (g + v) : (g - v)   // adding v to short side
                let residual = abs(newG)
                guard residual < abs(g) else { continue }                     // must strictly close the gap
                if best == nil || betterFairness(c, residual, than: best!.cand, best!.residual,
                                                 includePicks: input.options.includePicks) {
                    best = (c, residual)
                }
            }
            guard let chosen = best else { return }                            // no legal improving add
            let mv = BalanceMove(candidate: chosen.cand, toTeamId: shortTeam)
            additions.append(BalanceAddition(move: mv, reason: .fairness,
                                             detail: "\(chosen.cand.label) — added to balance the trade value."))
        }
    }

    /// Prefer: smaller residual gap, then a pick over a player (a sweetener),
    /// then less salary moved.
    private static func betterFairness(_ c: BalanceCandidate, _ residual: Double,
                                       than bc: BalanceCandidate, _ bResidual: Double,
                                       includePicks: Bool) -> Bool {
        if residual != bResidual { return residual < bResidual }
        if includePicks && c.isPlayer != bc.isPlayer { return !c.isPlayer }    // pick wins ties
        return c.salary < bc.salary
    }

    // MARK: - Escalation seam (Approach 2, deferred)

    /// Future bounded-optimal search plugs in here. Fires only when explicitly
    /// enabled (`escalationMaxPool > 0`) AND the combined candidate pool is
    /// small enough to enumerate. MVP keeps it dormant (returns nil).
    private static func escalateIfEligible(input: BalanceInput, legality: LegalityOracle,
                                           additions: [BalanceAddition]) -> BalanceResult? {
        let pool = input.candidatesA.count + input.candidatesB.count
        guard input.options.escalationMaxPool > 0, pool <= input.options.escalationMaxPool else { return nil }
        return nil   // OptimalStrategy not implemented in the MVP
    }
}
