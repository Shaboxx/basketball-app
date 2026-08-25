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
        let window = Array(eligible.sorted { $0.rating > $1.rating }
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
}
