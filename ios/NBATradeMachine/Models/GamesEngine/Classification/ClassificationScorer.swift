import Foundation

/// Scores a completed classification 0–100 against the model order (subjects
/// sorted by rating desc, ties broken by id asc — R6, deterministic). Bijective
/// modes use pairwise concordance (how many subject pairs are ordered the same
/// as the model). Tiers use average per-subject tier-band distance (adjacent-tier
/// errors earn partial credit). A malformed complete state (bijective mode with
/// duplicate destinations — only reachable by decoding, not by `assign`) scores 0
/// (R5).
nonisolated enum ClassificationScorer {

    static func score(_ state: ClassificationState) -> Int {
        // `> 1` is deliberate: a 1-subject "puzzle" has no pairs/ordering to score,
        // so it scores 0 rather than a meaningless 100. No shipped preset uses 1.
        guard state.status == .complete,
              state.assignments.count == state.subjects.count,
              state.subjects.count > 1 else { return 0 }
        // R5: bijective modes require unique destinations.
        if state.definition.config.mode.isBijective,
           Set(state.assignments.values).count != state.assignments.count { return 0 }
        // Model rank per subject id (0 = best). R6 deterministic tie-break by id.
        let ordered = state.subjects.sorted(by: ratingThenId)
        var modelRank: [String: Int] = [:]
        for (i, s) in ordered.enumerated() { modelRank[s.id] = i }

        switch state.definition.config.mode {
        case .totalOrder, .uniqueLabels:
            return concordanceScore(state.subjects, assignments: state.assignments,
                                    modelRank: modelRank)
        case .tiers:
            return tierScore(state, modelRank: modelRank)
        }
    }

    /// rating desc, then id asc — a stable strict weak ordering (extracted to keep
    /// the type-checker fast).
    private static func ratingThenId(_ a: GameEntityRecord, _ b: GameEntityRecord) -> Bool {
        if a.rating != b.rating { return a.rating > b.rating }
        return a.id < b.id
    }

    /// % of subject pairs ordered the same as the model (Kendall-style).
    private static func concordanceScore(_ subjects: [GameEntityRecord],
                                         assignments: [String: Int],
                                         modelRank: [String: Int]) -> Int {
        let ids = subjects.map(\.id)
        var concordant = 0, total = 0
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                guard let ui = assignments[ids[i]], let uj = assignments[ids[j]],
                      let mi = modelRank[ids[i]], let mj = modelRank[ids[j]] else { continue }
                total += 1
                if (ui < uj) == (mi < mj) { concordant += 1 }
            }
        }
        guard total > 0 else { return 0 }
        return Int((Double(concordant) / Double(total) * 100).rounded())
    }

    /// Average of (1 - tierDistance / maxDistance) across subjects, × 100.
    private static func tierScore(_ state: ClassificationState,
                                  modelRank: [String: Int]) -> Int {
        let n = state.subjects.count
        let tiers = state.definition.config.labels.count
        guard tiers > 0 else { return 0 }
        let maxDist = max(1, tiers - 1)
        func modelTier(_ id: String) -> Int {
            let r = modelRank[id] ?? 0
            return min(tiers - 1, r * tiers / n)
        }
        var acc = 0.0
        for s in state.subjects {
            let user = state.assignments[s.id] ?? 0
            let dist = abs(user - modelTier(s.id))
            acc += 1.0 - Double(dist) / Double(maxDist)
        }
        return Int((acc / Double(n) * 100).rounded())
    }
}
