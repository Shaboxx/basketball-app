import Foundation

nonisolated enum GuessStatus: String, Codable, Equatable { case active, won, lost }

nonisolated enum GuessError: Error, Equatable {
    case emptyPool, noClues, alreadyFinished, noMoreClues, unknownEntity
}

/// One revealed clue: the source field plus a display-ready line rendered from the
/// target at `initialize`. Rendering once (deterministically) keeps the view free
/// of record-formatting logic and makes the clue text part of the replay-stable
/// state (same seed ⇒ identical clue strings).
nonisolated struct GuessClue: Codable, Equatable {
    let field: GameField
    let text: String        // e.g. "Decade: 2010s", "Points per game: 27.0"
}

/// The whole GUESS session — a pure value. Construct ONLY via `GuessEngine.
/// initialize`. `orderedClues` is the full clue list for the target (already
/// filtered to fields present + clamped to maxClues); `revealedCount` is how many
/// are visible; `guessesRemaining` counts down one per attempt.
nonisolated struct GuessState: Codable, Equatable {
    let definition: GuessDefinition
    let pool: [GameEntityRecord]        // the answer set the picker searches (deduped)
    let targetId: String                // the mystery entity's id
    let orderedClues: [GuessClue]       // full sequence; count == maxClues (effective)
    var revealedCount: Int              // 1…orderedClues.count clues shown so far
    var guessesRemaining: Int           // wrong guesses left before a loss
    var rng: SeededRNG
    var status: GuessStatus
    var lastGuessCorrect: Bool?

    func entity(_ id: String) -> GameEntityRecord? { pool.first { $0.id == id } }
    var target: GameEntityRecord? { entity(targetId) }
    /// The clues currently visible to the player.
    var revealedClues: [GuessClue] { Array(orderedClues.prefix(revealedCount)) }
}

nonisolated enum GuessEngine {

    /// Seed a mystery target from the top `candidatePoolSize` by rating, build its
    /// ordered clue list (only fields the target actually has, in config order,
    /// clamped to maxClues), and open with one clue revealed. Deterministic under
    /// `seed`; ties broken by id ascending (stable candidate set).
    static func initialize(definition: GuessDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> GuessState {
        // R3: dedup by id (the picker + answer-matching key on id).
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { throw GuessError.emptyPool }

        let cfg = definition.config
        let topN = max(1, min(cfg.candidatePoolSize, unique.count))
        let candidates = Array(unique.sorted {
            $0.rating != $1.rating ? $0.rating > $1.rating : $0.id < $1.id
        }.prefix(topN))
        var rng = SeededRNG(seed: seed)
        // Draw the target from the candidate set (recognizable answers).
        guard let target = candidates.shuffled(using: &rng).first else {
            throw GuessError.emptyPool
        }

        // Build clues from the config's ordered fields, skipping ones absent on the
        // target (thin-pool tolerance — never crash / never show a blank clue).
        var clues: [GuessClue] = []
        for field in cfg.clueFields {
            guard let value = target.value(for: field) else { continue }
            clues.append(GuessClue(field: field, text: render(field: field, value: value)))
            if clues.count >= cfg.maxClues { break }
        }
        guard !clues.isEmpty else { throw GuessError.noClues }

        return GuessState(definition: definition,
                          pool: unique,
                          targetId: target.id,
                          orderedClues: clues,
                          revealedCount: 1,
                          guessesRemaining: clues.count,
                          rng: rng,
                          status: .active,
                          lastGuessCorrect: nil)
    }

    /// Reveal the next clue. No-op-safe once all are shown (throws), never exceeds
    /// the built clue count, and rejects action on a finished game (R4).
    static func revealNextClue(_ state: GuessState) throws -> GuessState {
        guard state.status == .active else { throw GuessError.alreadyFinished }
        guard state.revealedCount < state.orderedClues.count else {
            throw GuessError.noMoreClues
        }
        var next = state
        next.revealedCount += 1
        return next
    }

    /// Submit a guess (by pool id). Correct → won (score computed by GuessScorer
    /// from `revealedCount`). Wrong → decrement guesses; running out (or a wrong
    /// guess with all clues shown) ends the game as a loss.
    static func guess(_ state: GuessState, subjectId: String) throws -> GuessState {
        guard state.status == .active else { throw GuessError.alreadyFinished }
        guard state.entity(subjectId) != nil else { throw GuessError.unknownEntity }
        var next = state
        if subjectId == state.targetId {
            next.lastGuessCorrect = true
            next.status = .won
            return next
        }
        next.lastGuessCorrect = false
        next.guessesRemaining = max(0, next.guessesRemaining - 1)
        if next.guessesRemaining == 0 {
            next.status = .lost
            // Reveal everything on a loss so the finished card can show the answer.
            next.revealedCount = next.orderedClues.count
        } else if next.revealedCount < next.orderedClues.count {
            // A wrong guess auto-advances to the next clue (keeps the loop moving).
            next.revealedCount += 1
        }
        return next
    }

    /// The score a WON state earns (0 for active/lost). Convenience over
    /// `GuessScorer` so the store/view have one call site.
    static func score(_ state: GuessState) -> Int {
        GuessScorer.score(won: state.status == .won,
                          cluesUsed: state.revealedCount,
                          maxClues: state.orderedClues.count)
    }

    // MARK: - Clue rendering

    /// Render a clue line for a field/value. Kept deterministic + pure so the clue
    /// strings are part of the replay-stable state. Percentages render as %, decade
    /// as "2010s", season as its label, awards/draft as counts.
    static func render(field: GameField, value: GameFieldValue) -> String {
        switch (field, value) {
        case (.decadeStartYear, .number(let n)):
            return "Decade: \(Int(n))s"
        case (.seasonStartYear, .number(let n)):
            return "Season starts: \(Int(n))"
        case (.seasonLabel, .string(let s)):
            return "Season: \(s)"
        case (.team, .string(let s)):
            return "Team: \(s)"
        case (.position, .string(let s)):
            return "Position: \(s)"
        case (.age, .number(let n)):
            return "Age: \(Int(n.rounded()))"
        case (.salary, .number(let n)):
            return "Salary: $\(Int(n) / 1_000_000)M"
        case (.rating, .number(let n)):
            return "Rating: \(fmt1(n))"
        case (.netRating, .number(let n)):
            return "Net rating: \(fmt1(n))"
        case (.pts, .number(let n)):    return "Points per game: \(fmt1(n))"
        case (.reb, .number(let n)):    return "Rebounds per game: \(fmt1(n))"
        case (.ast, .number(let n)):    return "Assists per game: \(fmt1(n))"
        case (.stl, .number(let n)):    return "Steals per game: \(fmt1(n))"
        case (.blk, .number(let n)):    return "Blocks per game: \(fmt1(n))"
        case (.tov, .number(let n)):    return "Turnovers per game: \(fmt1(n))"
        case (.fgPct, .number(let n)):     return "Field-goal %: \(pct(n))"
        case (.threePct, .number(let n)):  return "Three-point %: \(pct(n))"
        case (.ftPct, .number(let n)):     return "Free-throw %: \(pct(n))"
        case (.tsPct, .number(let n)):     return "True-shooting %: \(pct(n))"
        case (.usgPct, .number(let n)):    return "Usage %: \(pct(n))"
        case (.pie, .number(let n)):       return "PIE: \(pct(n))"
        case (.careerRings, .number(let n)):      return "Career rings: \(Int(n))"
        case (.careerMvp, .number(let n)):        return "Career MVPs: \(Int(n))"
        case (.careerFinalsMvp, .number(let n)):  return "Finals MVPs: \(Int(n))"
        case (.careerAllNba, .number(let n)):     return "All-NBA teams: \(Int(n))"
        case (.careerAllStar, .number(let n)):    return "All-Star selections: \(Int(n))"
        case (.careerAllDefense, .number(let n)): return "All-Defense teams: \(Int(n))"
        case (.draftYear, .number(let n)):   return "Draft year: \(Int(n))"
        case (.draftRound, .number(let n)):  return "Draft round: \(Int(n))"
        case (.draftPick, .number(let n)):   return "Draft pick: \(Int(n))"
        default:
            // A field whose typed value doesn't match its expected case (shouldn't
            // happen) still renders something rather than crashing.
            switch value {
            case .string(let s): return "\(field.rawValue): \(s)"
            case .number(let n): return "\(field.rawValue): \(fmt1(n))"
            }
        }
    }

    private static func fmt1(_ n: Double) -> String { String(format: "%.1f", n) }
    /// Rate stats in the data are 0…1 fractions; show as a whole-number percent.
    private static func pct(_ n: Double) -> String {
        let p = n <= 1.0 ? n * 100 : n     // tolerate a value already in 0…100
        return String(format: "%.0f%%", p)
    }
}
