import Foundation

/// The "server-side definition validation" done CLIENT-side (spec §28) by reusing
/// the in-repo feasibility solver. This is the exact function a future Cloud
/// Function would run server-side before publishing a user definition. Pure +
/// nonisolated so it runs in tests and in the creator store identically.
nonisolated enum GameDefinitionValidator {

    nonisolated enum ValidationError: Error, Equatable {
        case emptyPool               // no eligible entities after the pool filter
        case emptyTitle              // a saved game needs a name
        case infeasibleDefinition    // GameFeasibility.canComplete == false (roster)
        case incoherentModifiers     // e.g. rerolls without randomOffer
        case degenerateScoring       // too few distinct entities for the engine
        case invalidConfig           // a malformed engine config (bad field size, counts)
    }

    /// Validate a draft against the LIVE pool. `participantCount` is the worst
    /// case the game must support (roster feasibility is per-seat under a shared
    /// pool); default 1 (a solo game). For non-roster families it checks the
    /// same min-distinct preconditions each engine's `initialize` enforces.
    static func validate(_ draft: GameDraft, pool: [GameEntityRecord],
                         participantCount: Int = 1) -> Result<Void, ValidationError> {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyTitle)
        }
        switch draft.payload {
        case .roster(let def):        return validateRoster(def, pool: pool, participantCount: participantCount)
        case .classification(let def): return validateClassification(def, pool: pool)
        case .compare(let def):       return validateCompare(def, pool: pool)
        case .bracket(let def):       return validateBracket(def, pool: pool)
        }
    }

    // MARK: - Roster / composite

    private static func validateRoster(_ def: GameDefinition, pool: [GameEntityRecord],
                                       participantCount: Int) -> Result<Void, ValidationError> {
        // Reject the same incoherent modifier combo the engine's initialize does.
        if let sa = def.specialActions, sa.rerolls > 0, def.selection.method != .randomOffer {
            return .failure(.incoherentModifiers)
        }
        let eligible = pool.filter { e in
            def.entityConstraints.allSatisfy { GameConstraintEvaluator.satisfies(e, $0) }
        }
        guard !eligible.isEmpty else { return .failure(.emptyPool) }
        // Duplicate slot ids would false-positive feasibility (engine guards it too).
        let slotIds = def.roster.slots.map(\.id)
        guard Set(slotIds).count == slotIds.count, !slotIds.isEmpty else {
            return .failure(.invalidConfig)
        }
        // The §28 backtracking already in-repo — the exact gate the engine uses.
        guard GameFeasibility.canComplete(definition: def,
                                          participantCount: max(1, participantCount),
                                          pool: eligible) else {
            return .failure(.infeasibleDefinition)
        }
        return .success(())
    }

    // MARK: - Classification

    private static func validateClassification(_ def: ClassificationDefinition,
                                               pool: [GameEntityRecord]) -> Result<Void, ValidationError> {
        let cfg = def.config
        guard cfg.subjectCount > 0, cfg.candidatePoolSize > 0 else {
            return .failure(.invalidConfig)
        }
        if (cfg.mode == .tiers || cfg.mode == .uniqueLabels), cfg.labels.isEmpty {
            return .failure(.invalidConfig)
        }
        if cfg.mode == .uniqueLabels, cfg.subjectCount != cfg.labels.count {
            return .failure(.invalidConfig)
        }
        // Need at least subjectCount distinct entities to draw a puzzle.
        let distinct = Set(pool.map(\.id)).count
        guard distinct >= cfg.subjectCount else { return .failure(.degenerateScoring) }
        return .success(())
    }

    // MARK: - Compare

    private static func validateCompare(_ def: CompareDefinition,
                                        pool: [GameEntityRecord]) -> Result<Void, ValidationError> {
        let metric = def.config.metric
        var seen = Set<String>()
        let comparable = pool.filter { seen.insert($0.id).inserted }.filter { metric.value($0) != nil }
        let distinctValues = Set(comparable.compactMap { metric.value($0) })
        // Same precondition CompareEngine.initialize enforces: ≥2 comparable AND
        // ≥2 distinct metric values (else no round has a real answer).
        guard comparable.count >= 2, distinctValues.count >= 2 else {
            return .failure(.degenerateScoring)
        }
        return .success(())
    }

    // MARK: - Bracket

    private static func validateBracket(_ def: BracketDefinition,
                                        pool: [GameEntityRecord]) -> Result<Void, ValidationError> {
        guard BracketEngine.validFieldSizes.contains(def.fieldSize) else {
            return .failure(.invalidConfig)
        }
        var seen = Set<String>()
        let eligible = pool.filter { e in
            def.entityConstraints.allSatisfy { GameConstraintEvaluator.satisfies(e, $0) }
        }.filter { seen.insert($0.id).inserted }
        guard eligible.count >= def.fieldSize else { return .failure(.degenerateScoring) }
        return .success(())
    }
}
