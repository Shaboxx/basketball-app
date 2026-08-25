import Foundation

nonisolated enum ClassificationStatus: String, Codable, Equatable { case assigning, complete }

nonisolated enum ClassificationError: Error, Equatable {
    case invalidConfig, notEnoughSubjects, invalidDestination, destinationTaken, unknownSubject, alreadyComplete
}

/// The whole classification session — a pure value. Construct ONLY via
/// `ClassificationEngine.initialize` (config invariants — unique subject ids,
/// bijective destination counts — are established there). A decoded blob that
/// bypasses initialize is the caller's risk; the scorer defends against
/// malformed bijective states (R5).
nonisolated struct ClassificationState: Codable, Equatable {
    let definition: ClassificationDefinition
    let subjects: [GameEntityRecord]
    var assignments: [String: Int]      // subjectId → destination index
    var status: ClassificationStatus
}

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

    static func initialize(definition: ClassificationDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> ClassificationState {
        let cfg = definition.config
        // R2: validate config before generating (negatives would trap prefix).
        guard cfg.subjectCount > 0, cfg.candidatePoolSize > 0 else {
            throw ClassificationError.invalidConfig
        }
        if (cfg.mode == .tiers || cfg.mode == .uniqueLabels), cfg.labels.isEmpty {
            throw ClassificationError.invalidConfig
        }
        if cfg.mode == .uniqueLabels, cfg.subjectCount != cfg.labels.count {
            throw ClassificationError.invalidConfig
        }
        let subjects = generateSubjects(pool: pool, config: cfg, seed: seed)
        guard subjects.count == cfg.subjectCount else {
            throw ClassificationError.notEnoughSubjects
        }
        return ClassificationState(definition: definition, subjects: subjects,
                                   assignments: [:], status: .assigning)
    }

    /// Assign a subject to a destination index. Bijective modes reject a taken
    /// destination (but re-assigning the SAME subject moves it, freeing its old
    /// spot). Tiers allow reuse. Rejects action on a completed game (R4).
    static func assign(_ state: ClassificationState, subjectId: String,
                       destination: Int) throws -> ClassificationState {
        guard state.status == .assigning else { throw ClassificationError.alreadyComplete }
        let cfg = state.definition.config
        guard state.subjects.contains(where: { $0.id == subjectId }) else {
            throw ClassificationError.unknownSubject
        }
        guard destination >= 0, destination < cfg.destinationCount else {
            throw ClassificationError.invalidDestination
        }
        if cfg.mode.isBijective {
            let taken = state.assignments.first {
                $0.value == destination && $0.key != subjectId
            }
            if taken != nil { throw ClassificationError.destinationTaken }
        }
        var next = state
        next.assignments[subjectId] = destination
        if next.assignments.count == next.subjects.count {
            next.status = .complete
        }
        return next
    }
}
