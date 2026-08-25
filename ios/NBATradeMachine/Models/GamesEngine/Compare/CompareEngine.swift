import Foundation

nonisolated enum CompareStatus: String, Codable, Equatable { case active, complete }

nonisolated enum CompareError: Error, Equatable {
    case notEnoughComparable, notInPair, unknownEntity, gameComplete
}

/// The whole compare session — a pure value.
nonisolated struct CompareState: Codable, Equatable {
    let definition: CompareDefinition
    let pool: [GameEntityRecord]        // only entities with the metric present
    var pair: [String]                  // the two ids on offer (count 2)
    var rng: SeededRNG
    var score: Int                      // current streak
    var status: CompareStatus
    var lastCorrect: Bool?              // result of the most recent guess

    func entity(_ id: String) -> GameEntityRecord? { pool.first { $0.id == id } }
}

nonisolated enum CompareEngine {

    static func initialize(definition: CompareDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> CompareState {
        let metric = definition.config.metric
        // R3: dedup by id (a duplicate id would corrupt pair lookups).
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        let comparable = unique.filter { metric.value($0) != nil }
        // R1: need ≥2 entities AND ≥2 DISTINCT metric values (else no round has a
        // real answer).
        let distinctValues = Set(comparable.compactMap { metric.value($0) })
        guard comparable.count >= 2, distinctValues.count >= 2 else {
            throw CompareError.notEnoughComparable
        }
        var rng = SeededRNG(seed: seed)
        let pair = drawPair(comparable, metric: metric, rng: &rng)
        return CompareState(definition: definition, pool: comparable, pair: pair,
                            rng: rng, score: 0, status: .active, lastCorrect: nil)
    }

    /// Draw two ids whose metric values DIFFER (R1: guaranteed to exist once
    /// initialize confirmed ≥2 distinct values, so there's always a right answer).
    private static func drawPair(_ pool: [GameEntityRecord], metric: CompareMetric,
                                 rng: inout SeededRNG) -> [String] {
        let shuffled = pool.shuffled(using: &rng)
        let a = shuffled[0]
        if let b = shuffled.dropFirst().first(where: { metric.value($0) != metric.value(a) }) {
            return [a.id, b.id]
        }
        return [shuffled[0].id, shuffled[1].id]   // unreachable post-init
    }

    static func guess(_ state: CompareState, subjectId: String) throws -> CompareState {
        guard state.status == .active else { throw CompareError.gameComplete }   // R4
        guard state.pair.contains(subjectId) else { throw CompareError.notInPair }
        guard let a = state.entity(state.pair[0]), let b = state.entity(state.pair[1]) else {
            throw CompareError.unknownEntity
        }
        let metric = state.definition.config.metric
        // `?? 0` is dead-safe (pool is pre-filtered nil-free at init). drawPair
        // guarantees va != vb for every offered pair, so the `>=`/`<=` tie edge
        // is never exercised on a real round — it only picks a side for a
        // decoded/bypassed equal-value state; don't "fix" it into a bug.
        let va = metric.value(a) ?? 0, vb = metric.value(b) ?? 0
        let correctId: String
        switch state.definition.config.direction {
        case .higher: correctId = va >= vb ? a.id : b.id
        case .lower:  correctId = va <= vb ? a.id : b.id
        }
        var next = state
        let wasCorrect = subjectId == correctId
        next.lastCorrect = wasCorrect
        if wasCorrect {
            next.score += 1
            var rng = next.rng
            next.pair = drawPair(next.pool, metric: metric, rng: &rng)
            next.rng = rng
        } else {
            next.status = .complete
        }
        return next
    }
}
