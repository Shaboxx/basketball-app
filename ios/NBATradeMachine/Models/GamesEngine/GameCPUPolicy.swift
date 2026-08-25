import Foundation

/// CPU picker: from the seat's legal picks, rank by rating, keep the top
/// `candidateWindow`, choose one weighted toward the front (so CPUs are strong
/// but not identical every game), then fill the most constrained valid slot so
/// flexible slots stay open. Deterministic under the caller's RNG — the same
/// policy will drive online auto-pick timeouts in roadmap Phase 7.
nonisolated enum GameCPUPolicy {

    static let candidateWindow = 4

    static func choosePick(_ state: RosterGameState, seat: Int,
                           rng: inout SeededRNG) -> (entityId: String, slotId: String)? {
        let eligible = RosterConstructionEngine.eligibleEntities(state, seat: seat)
        guard !eligible.isEmpty else { return nil }
        // Budget reserve: in an economy game, don't spend so much on this pick
        // that the remaining open slots can't be filled at the cheapest going
        // rate — otherwise a greedy-by-rating CPU strands itself with a partial
        // roster. Reserve (openSlots-1) × cheapest-eligible; only pick within
        // what's left. Fall back to the full set if even the cheapest exceeds
        // the reserve (do the best it can — honest-finish still applies).
        let candidates = budgetReserved(eligible, state, seat: seat)
        let window = Array(candidates.sorted { $0.rating > $1.rating }
            .prefix(candidateWindow))
        // Weights window.count, …, 1 — front-loaded.
        let weights = (0..<window.count).map { window.count - $0 }
        var roll = Int(rng.next() % UInt64(weights.reduce(0, +)))
        var chosen = window[0]
        for (i, w) in weights.enumerated() {
            if roll < w { chosen = window[i]; break }
            roll -= w
        }
        let slots = RosterConstructionEngine.validSlots(state, seat: seat, entity: chosen)
        let slot = slots.min { freedom($0) < freedom($1) }!  // eligibility ⇒ non-empty
        return (chosen.id, slot.id)
    }

    /// Lower = more constrained; positionless slots are unbounded.
    private static func freedom(_ slot: RosterSlot) -> Int {
        slot.allowedPositions.isEmpty ? Int.max : slot.allowedPositions.count
    }

    /// Restrict `eligible` to picks that still leave the roster COMPLETABLE — a
    /// candidate is kept only if, after buying it for its most-constrained valid
    /// slot, the remaining open slots can be filled (position- AND budget-aware)
    /// from the rest of the pool within the remaining budget. Reuses the tested
    /// `GameFeasibility` backtracker so it's correct for positional rosters like
    /// flexFive, not just positionless. No-op without an economy or on the last
    /// slot. Returns the top-rated safe candidates (up to `candidateWindow`);
    /// falls back to the full set if none are safe (honest-finish still applies).
    private static func budgetReserved(_ eligible: [GameEntityRecord],
                                       _ state: RosterGameState,
                                       seat: Int) -> [GameEntityRecord] {
        guard let econ = state.definition.economy,
              let budget = state.budgets?[seat] else { return eligible }
        let filledIds = Set(state.rosters[seat].map(\.slotId))
        let openSlots = state.definition.roster.slots.filter { !filledIds.contains($0.id) }
        guard openSlots.count > 1 else { return eligible }   // last slot: any affordable pick completes it
        let ownIds = Set(state.rosters[seat].map(\.entity.id))
        let shared = state.definition.selection.sharedPool
        let available = state.pool.filter { p in
            !ownIds.contains(p.id) && !(shared && state.pickedIds.contains(p.id))
        }
        var safe: [GameEntityRecord] = []
        for cand in eligible.sorted(by: { $0.rating > $1.rating }) {
            guard let slot = openSlots.filter({ $0.accepts(cand) })
                .min(by: { freedom($0) < freedom($1) }) else { continue }
            let remainingSlots = openSlots.filter { $0.id != slot.id }
            let remainingPool = available.filter { $0.id != cand.id }
            let reducedEcon = EconomyConfig(pricingMethod: econ.pricingMethod,
                                            startingBudget: budget - econ.price(cand))
            // FUTURE: fill starts from an EMPTY roster, so roster-scope
            // constraints (uniqueBy/totalAtMost/minCountWhere) are checked
            // against only the remaining picks, not the seat's already-drafted
            // players. Exact for every shipping preset (Fantasy Salary Cap has
            // no rosterConstraints; the one uniqueBy game has no economy). Before
            // an economy+rosterConstraint game ships, seed fill with the seat's
            // current roster + candidate so those aggregates count correctly.
            if GameFeasibility.fill(slots: remainingSlots, from: remainingPool,
                                    constraints: state.definition.rosterConstraints,
                                    economy: reducedEcon) != nil {
                safe.append(cand)
                if safe.count >= candidateWindow { break }
            }
        }
        return safe.isEmpty ? eligible : safe
    }
}
