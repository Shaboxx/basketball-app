import Foundation

/// Pre-play feasibility (spec §28): can every participant fill every slot from
/// the eligible pool without breaking roster constraints? One roster is solved
/// by exact backtracking, most-restrictive slot first. Multi-participant shared
/// pools are checked by sequential witness fills — sufficient but not exhaustive
/// across participants; a false negative needs a pool barely bigger than the
/// combined rosters, not reachable at current pool sizes; presets are covered
/// by tests.
nonisolated enum GameFeasibility {

    /// Backtracking node budget per `fill` call. Exhausting it returns nil
    /// ("not provably feasible") — conservative on purpose: an over-budget
    /// definition is rejected instead of hanging a main-thread initialize.
    static let nodeBudget = 50_000

    /// `pool` must ALREADY satisfy the definition's `entityConstraints`
    /// (the engine's initialize filters first) — this checks roster-scope
    /// feasibility only.
    static func canComplete(definition: GameDefinition, participantCount: Int,
                            pool: [GameEntityRecord]) -> Bool {
        guard participantCount >= 1, !definition.roster.slots.isEmpty else { return false }
        guard definition.selection.sharedPool else {
            return fill(slots: definition.roster.slots, from: pool,
                        constraints: definition.rosterConstraints) != nil
        }
        var available = pool
        for _ in 0..<participantCount {
            guard let used = fill(slots: definition.roster.slots, from: available,
                                  constraints: definition.rosterConstraints) else {
                return false
            }
            let usedIds = Set(used.map(\.id))
            available.removeAll { usedIds.contains($0.id) }
        }
        return true
    }

    /// A witness assignment filling every slot, or nil if impossible
    /// (or not provable within `nodeBudget`).
    static func fill(slots: [RosterSlot], from pool: [GameEntityRecord],
                     constraints: [RosterConstraint]) -> [GameEntityRecord]? {
        var budget = nodeBudget
        return fillRec(remaining: slots, roster: [], pool: pool,
                       constraints: constraints, budget: &budget)
    }

    private static func fillRec(remaining: [RosterSlot], roster: [GameEntityRecord],
                                pool: [GameEntityRecord],
                                constraints: [RosterConstraint],
                                budget: inout Int) -> [GameEntityRecord]? {
        budget -= 1
        guard budget >= 0 else { return nil }
        if remaining.isEmpty {
            return GameConstraintEvaluator.satisfiesCompleted(roster, constraints: constraints)
                ? roster : nil
        }
        // minCountWhere lookahead: it never gates picks, so without this an
        // infeasible floor would force exhausting the whole tree. Fail fast
        // when even the best case (every remaining slot filled by a matching
        // pool player) can't reach the required count.
        for constraint in constraints {
            if case .minCountWhere(let cond, let minCount) = constraint {
                let have = roster.filter { GameConstraintEvaluator.satisfies($0, cond) }.count
                let possible = min(remaining.count,
                                   pool.filter { GameConstraintEvaluator.satisfies($0, cond) }.count)
                if have + possible < minCount { return nil }
            }
        }
        // Most restrictive slot first (fewest legal candidates) — prunes hardest.
        let ranked = remaining.map { slot in
            (slot, pool.filter { e in
                slot.accepts(e) && GameConstraintEvaluator.allowsPick(
                    roster: roster, candidate: e, constraints: constraints)
            })
        }.min { $0.1.count < $1.1.count }!
        let (slot, candidates) = ranked
        guard !candidates.isEmpty else { return nil }
        let rest = remaining.filter { $0.id != slot.id }
        for candidate in candidates {
            var nextPool = pool
            nextPool.removeAll { $0.id == candidate.id }
            if let solution = fillRec(remaining: rest, roster: roster + [candidate],
                                      pool: nextPool, constraints: constraints,
                                      budget: &budget) {
                return solution
            }
        }
        return nil
    }
}
