import Foundation

nonisolated enum ClassificationEngine {

    /// Draw `subjectCount` subjects (seeded) from the top `candidatePoolSize`
    /// players by rating. Deterministic under `seed`; clamps to the pool size.
    /// Dedups the pool by id (R3) and breaks rating ties by id ascending (R6) so
    /// the candidate set and the later model order are stable and reproducible.
    static func generateSubjects(pool: [GameEntityRecord],
                                 config: ClassificationConfig,
                                 seed: UInt64) -> [GameEntityRecord] {
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        let topN = max(0, min(config.candidatePoolSize, unique.count))
        let candidates = Array(unique.sorted {
            $0.rating != $1.rating ? $0.rating > $1.rating : $0.id < $1.id
        }.prefix(topN))
        var rng = SeededRNG(seed: seed)
        let count = max(0, min(config.subjectCount, candidates.count))
        return Array(candidates.shuffled(using: &rng).prefix(count))
    }
}
