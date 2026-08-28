import Foundation

nonisolated enum SurvivorStatus: String, Codable, Equatable { case playing, lost }

nonisolated enum SurvivorError: Error, Equatable {
    case noPrompts, emptyPool, alreadyFinished, unknownEntity, alreadyUsed, doesNotSatisfy
}

/// The whole SURVIVOR session — a pure value. Construct ONLY via
/// `SurvivorEngine.initialize`. `promptOrder` is the seeded prompt sequence
/// (indices into the definition's prompts); `promptCursor` points at the current
/// one; `usedIds` is the no-reuse tracker; `livesRemaining` counts down.
nonisolated struct SurvivorState: Codable, Equatable {
    let definition: SurvivorDefinition
    let pool: [GameEntityRecord]        // the answer set the picker searches (deduped)
    var promptOrder: [Int]              // seeded order of prompt indices (extended with fresh seeded cycles as the streak runs on)
    var promptCursor: Int               // index into promptOrder
    var usedIds: Set<String>            // no-reuse across the whole run
    var streak: Int                     // correct answers so far
    var livesRemaining: Int
    var rng: SeededRNG
    var status: SurvivorStatus
    var lastAnswerCorrect: Bool?

    func entity(_ id: String) -> GameEntityRecord? { pool.first { $0.id == id } }

    /// The prompt awaiting an answer (nil only in a malformed decoded state).
    var currentPrompt: SurvivorPrompt? {
        guard promptCursor >= 0, promptCursor < promptOrder.count else { return nil }
        let idx = promptOrder[promptCursor]
        guard idx >= 0, idx < definition.config.prompts.count else { return nil }
        return definition.config.prompts[idx]
    }

    /// Whether an unused pool entity still satisfies the current prompt (used by
    /// the view to grey out exhausted prompts / detect a dead end).
    func hasRemainingAnswer(for prompt: SurvivorPrompt) -> Bool {
        pool.contains { !usedIds.contains($0.id) && prompt.matches($0) }
    }
}

nonisolated enum SurvivorEngine {

    /// Seed the prompt sequence and open the first prompt. Deterministic under
    /// `seed`. Requires at least one prompt AND a non-empty pool; a prompt that no
    /// pool entity satisfies is TOLERATED here (it may still be skipped at play
    /// time) but the sequence is built from ALL configured prompts.
    static func initialize(definition: SurvivorDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> SurvivorState {
        guard !definition.config.prompts.isEmpty else { throw SurvivorError.noPrompts }
        // R3: dedup by id (picker + used-tracker key on id).
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { throw SurvivorError.emptyPool }

        var rng = SeededRNG(seed: seed)
        let order = Array(0..<definition.config.prompts.count).shuffled(using: &rng)
        var state = SurvivorState(
            definition: definition, pool: unique, promptOrder: order,
            promptCursor: 0, usedIds: [], streak: 0,
            livesRemaining: max(1, definition.config.lives),
            rng: rng, status: .playing, lastAnswerCorrect: nil)
        // Advance the cursor past any leading prompt with no possible answer so the
        // player never opens on an unanswerable prompt (thin-pool tolerance).
        state = skipUnanswerablePrompts(state)
        return state
    }

    /// Submit an answer (a pool entity id). Correct + unused + satisfies → streak++
    /// and advance to the next (seeded) prompt. Already-used → error (no-reuse,
    /// no life lost — an illegal move, not a wrong one). Doesn't satisfy → a life
    /// is lost; running out ends the game.
    static func submitAnswer(_ state: SurvivorState, subjectId: String) throws -> SurvivorState {
        guard state.status == .playing else { throw SurvivorError.alreadyFinished }
        guard let entity = state.entity(subjectId) else { throw SurvivorError.unknownEntity }
        guard let prompt = state.currentPrompt else { throw SurvivorError.alreadyFinished }
        // No-reuse is an ILLEGAL move (reject without penalty) — the UI greys used
        // entities, so this is a guard against a bypassed selection.
        guard !state.usedIds.contains(subjectId) else { throw SurvivorError.alreadyUsed }

        var next = state
        if prompt.matches(entity) {
            next.lastAnswerCorrect = true
            next.streak += 1
            next.usedIds.insert(subjectId)
            next = advancePrompt(next)
        } else {
            next.lastAnswerCorrect = false
            next.livesRemaining = max(0, next.livesRemaining - 1)
            if next.livesRemaining == 0 { next.status = .lost }
        }
        return next
    }

    /// Skip the current prompt (voluntary give-up) — costs a life, advances. Ends
    /// the game if it was the last life.
    static func skip(_ state: SurvivorState) throws -> SurvivorState {
        guard state.status == .playing else { throw SurvivorError.alreadyFinished }
        var next = state
        next.lastAnswerCorrect = nil
        next.livesRemaining = max(0, next.livesRemaining - 1)
        if next.livesRemaining == 0 {
            next.status = .lost
        } else {
            next = advancePrompt(next)
        }
        return next
    }

    // MARK: - Prompt advancement

    /// Move to the next prompt in the seeded order; reshuffle+append a fresh cycle
    /// when the order is exhausted (endless survival). Then skip any prompt that
    /// has no remaining unused answer.
    private static func advancePrompt(_ state: SurvivorState) -> SurvivorState {
        var next = state
        next.promptCursor += 1
        if next.promptCursor >= next.promptOrder.count {
            // Extend with a fresh seeded cycle so the streak can run indefinitely.
            var rng = next.rng
            let more = Array(0..<next.definition.config.prompts.count).shuffled(using: &rng)
            next.promptOrder += more
            next.rng = rng
        }
        return skipUnanswerablePrompts(next)
    }

    /// Advance the cursor past prompts with no remaining unused satisfying entity.
    /// Bounded so an all-exhausted pool can't loop forever — if every prompt in a
    /// full cycle is unanswerable, the game ends as a loss (nothing left to name).
    private static func skipUnanswerablePrompts(_ state: SurvivorState) -> SurvivorState {
        var next = state
        var scanned = 0
        let cycle = max(1, next.definition.config.prompts.count)
        while next.status == .playing, let prompt = next.currentPrompt,
              !next.hasRemainingAnswer(for: prompt) {
            next.promptCursor += 1
            scanned += 1
            // If a whole cycle of prompts is unanswerable, the pool is exhausted.
            if scanned >= cycle {
                next.status = .lost
                break
            }
            if next.promptCursor >= next.promptOrder.count {
                var rng = next.rng
                let more = Array(0..<next.definition.config.prompts.count).shuffled(using: &rng)
                next.promptOrder += more
                next.rng = rng
            }
        }
        return next
    }
}
