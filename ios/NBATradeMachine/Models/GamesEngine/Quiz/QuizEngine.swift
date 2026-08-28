import Foundation

nonisolated enum QuizStatus: String, Codable, Equatable { case answering, complete }

nonisolated enum QuizError: Error, Equatable {
    case notEnoughContent, invalidChoice, alreadyComplete, outOfQuestions
}

/// The whole QUIZ session — a pure value. All questions are built up front at
/// `initialize` (a one-time O(n) scan of the pool per template), so the answer
/// loop is O(1) and never touches the pool.
nonisolated struct QuizState: Codable, Equatable {
    let definition: QuizDefinition
    let questions: [QuizQuestion]
    var currentIndex: Int
    var score: Int                      // number answered correctly
    var status: QuizStatus
    var lastAnswerCorrect: Bool?

    var currentQuestion: QuizQuestion? {
        currentIndex >= 0 && currentIndex < questions.count ? questions[currentIndex] : nil
    }
}

nonisolated enum QuizEngine {

    /// Build every question up front from a seeded pool. Templates that can't be
    /// satisfied on the available pool are SKIPPED (thin-pool tolerance) rather
    /// than producing degenerate questions; if not a single question can be built,
    /// throws `notEnoughContent`.
    static func initialize(definition: QuizDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> QuizState {
        let cfg = definition.config
        guard cfg.choiceCount >= 2, cfg.questionCount >= 1, !cfg.templates.isEmpty else {
            throw QuizError.notEnoughContent
        }
        // R3: dedup by id (distractor uniqueness + argmax stability).
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        let topN = max(0, min(cfg.candidatePoolSize, unique.count))
        let candidates = Array(unique.sorted {
            $0.rating != $1.rating ? $0.rating > $1.rating : $0.id < $1.id
        }.prefix(topN))

        var rng = SeededRNG(seed: seed)
        var questions: [QuizQuestion] = []
        var ordinal = 0
        // Cycle templates until we have questionCount questions or run dry.
        var attempts = 0
        let maxAttempts = cfg.questionCount * max(1, cfg.templates.count) * 4
        while questions.count < cfg.questionCount, attempts < maxAttempts {
            let template = cfg.templates[attempts % cfg.templates.count]
            attempts += 1
            if let q = buildQuestion(template, candidates: candidates,
                                     choiceCount: cfg.choiceCount,
                                     ordinal: ordinal, rng: &rng) {
                questions.append(q)
                ordinal += 1
            }
        }
        guard !questions.isEmpty else { throw QuizError.notEnoughContent }

        return QuizState(definition: definition, questions: questions,
                         currentIndex: 0, score: 0, status: .answering,
                         lastAnswerCorrect: nil)
    }

    /// Answer the current question by choice index. Advances; completes after the
    /// last question. Rejects an out-of-range index or a completed game (R4).
    static func answer(_ state: QuizState, choiceIndex: Int) throws -> QuizState {
        guard state.status == .answering else { throw QuizError.alreadyComplete }
        guard let q = state.currentQuestion else { throw QuizError.outOfQuestions }
        guard choiceIndex >= 0, choiceIndex < q.choices.count else {
            throw QuizError.invalidChoice
        }
        var next = state
        let correct = choiceIndex == q.correctIndex
        next.lastAnswerCorrect = correct
        if correct { next.score += 1 }
        next.currentIndex += 1
        if next.currentIndex >= next.questions.count { next.status = .complete }
        return next
    }

    // MARK: - Per-template pure generators

    private static func buildQuestion(_ template: QuizTemplateKind,
                                      candidates: [GameEntityRecord],
                                      choiceCount: Int,
                                      ordinal: Int,
                                      rng: inout SeededRNG) -> QuizQuestion? {
        switch template {
        case .superlative(let field, let higherIsBetter):
            return superlative(field: field, higherIsBetter: higherIsBetter,
                               candidates: candidates, choiceCount: choiceCount,
                               ordinal: ordinal, rng: &rng)
        case .attributeLookup(let field):
            return attributeLookup(field: field, candidates: candidates,
                                   choiceCount: choiceCount, ordinal: ordinal, rng: &rng)
        case .whichSeason:
            return whichSeason(candidates: candidates, choiceCount: choiceCount,
                               ordinal: ordinal, rng: &rng)
        case .higherField(let field, let higherIsBetter):
            return higherField(field: field, higherIsBetter: higherIsBetter,
                               candidates: candidates, ordinal: ordinal, rng: &rng)
        }
    }

    /// "Which of these had the most <field>?" among a seeded sample of `choiceCount`
    /// distinct entities. The true argmax of the SAMPLE is the answer (scoped to the
    /// shown choices, not a whole-pool claim), so the answer is always among the
    /// choices. Skips entities missing the field (thin-pool tolerance).
    private static func superlative(field: GameField, higherIsBetter: Bool,
                                    candidates: [GameEntityRecord], choiceCount: Int,
                                    ordinal: Int, rng: inout SeededRNG) -> QuizQuestion? {
        let withField = candidates.filter { numeric($0, field) != nil }
        guard withField.count >= choiceCount else { return nil }
        let sample = Array(withField.shuffled(using: &rng).prefix(choiceCount))
        // Distinct values needed so there's an unambiguous winner.
        let values = sample.map { numeric($0, field)! }
        guard Set(values).count == sample.count else { return nil }
        let answer = higherIsBetter
            ? sample.max { numeric($0, field)! < numeric($1, field)! }!
            : sample.min { numeric($0, field)! < numeric($1, field)! }!
        let choices = sample.map { entityLabel($0) }
        let correctIndex = sample.firstIndex { $0.id == answer.id }!
        let stem = "Which of these had the most \(fieldNoun(field))?"
        return QuizQuestion(id: ordinal, stem: stem, choices: choices,
                            correctIndex: correctIndex)
    }

    /// "What was <player>'s <field>?" The true numeric value is the answer;
    /// distractors are plausible nearby values (±5…25% jitter), deduped.
    private static func attributeLookup(field: GameField,
                                        candidates: [GameEntityRecord], choiceCount: Int,
                                        ordinal: Int, rng: inout SeededRNG) -> QuizQuestion? {
        let withField = candidates.filter { numeric($0, field) != nil }
        guard let subject = withField.shuffled(using: &rng).first,
              let trueValue = numeric(subject, field) else { return nil }
        // Build plausible distractors around the true value. Dedupe on the VISIBLE
        // LABEL (not the raw double) so integer-formatted fields like `careerRings`
        // never show two identical-looking choices (e.g. 3.0 and 3.6 both → "3").
        var values: [Double] = [trueValue]
        var labels: Set<String> = [valueLabel(trueValue, field: field)]
        func tryAdd(_ candidate: Double) {
            let label = valueLabel(candidate, field: field)
            guard candidate != trueValue, !labels.contains(label) else { return }
            values.append(candidate)
            labels.insert(label)
        }
        for f in [0.6, 0.75, 0.9, 1.1, 1.25, 1.5, 0.5, 1.75].shuffled(using: &rng) {
            if values.count >= choiceCount { break }
            tryAdd(round1(trueValue * f))
        }
        // Fall back to additive offsets if multiplicative ones collided on labels.
        var offset = 1.0
        while values.count < choiceCount, offset <= 100 {
            tryAdd(round1(trueValue + offset))
            tryAdd(round1(trueValue - offset))
            offset += 1.0
        }
        guard values.count == choiceCount else { return nil }
        let shuffled = values.shuffled(using: &rng)
        let choices = shuffled.map { valueLabel($0, field: field) }
        guard let correctIndex = shuffled.firstIndex(of: trueValue) else { return nil }
        let stem = "What was \(entityLabel(subject))'s \(fieldNoun(field))?"
        return QuizQuestion(id: ordinal, stem: stem, choices: choices,
                            correctIndex: correctIndex)
    }

    /// "Which season did <player-season> belong to?" The subject's season label is
    /// the answer; distractors are other DISTINCT season labels in the pool. Needs
    /// `seasonLabel` populated (historical pool only).
    private static func whichSeason(candidates: [GameEntityRecord], choiceCount: Int,
                                    ordinal: Int, rng: inout SeededRNG) -> QuizQuestion? {
        let withSeason = candidates.filter { $0.seasonLabel != nil }
        guard let subject = withSeason.shuffled(using: &rng).first,
              let trueSeason = subject.seasonLabel else { return nil }
        let otherSeasons = Array(Set(withSeason.compactMap { $0.seasonLabel })
            .subtracting([trueSeason])).sorted()
        guard otherSeasons.count >= choiceCount - 1 else { return nil }
        let distractors = Array(otherSeasons.shuffled(using: &rng).prefix(choiceCount - 1))
        let all = ([trueSeason] + distractors).shuffled(using: &rng)
        guard let correctIndex = all.firstIndex(of: trueSeason) else { return nil }
        let stem = "Which season was \(subject.name)'s?"
        return QuizQuestion(id: ordinal, stem: stem, choices: all,
                            correctIndex: correctIndex)
    }

    /// Two-choice "Which player had the higher/lower <field>?" over two sampled
    /// entities with DIFFERING field values (so there's a real answer). Ignores
    /// `choiceCount` (always 2).
    private static func higherField(field: GameField, higherIsBetter: Bool,
                                    candidates: [GameEntityRecord],
                                    ordinal: Int, rng: inout SeededRNG) -> QuizQuestion? {
        let withField = candidates.filter { numeric($0, field) != nil }
        guard withField.count >= 2 else { return nil }
        let shuffled = withField.shuffled(using: &rng)
        let a = shuffled[0]
        guard let b = shuffled.dropFirst().first(where: {
            numeric($0, field)! != numeric(a, field)!
        }) else { return nil }
        let va = numeric(a, field)!, vb = numeric(b, field)!
        let aWins = higherIsBetter ? va > vb : va < vb
        let choices = [entityLabel(a), entityLabel(b)]
        let correctIndex = aWins ? 0 : 1
        let stem = "Which had the \(higherIsBetter ? "higher" : "lower") \(fieldNoun(field))?"
        return QuizQuestion(id: ordinal, stem: stem, choices: choices,
                            correctIndex: correctIndex)
    }

    // MARK: - Helpers

    /// The numeric value of a field on an entity (nil if absent or non-numeric).
    static func numeric(_ e: GameEntityRecord, _ field: GameField) -> Double? {
        if case .number(let n)? = e.value(for: field) { return n }
        return nil
    }

    /// A disambiguating label: name plus season/team when present (14.5k dup names).
    static func entityLabel(_ e: GameEntityRecord) -> String {
        if let s = e.seasonLabel { return "\(e.name) (\(s))" }
        return e.name
    }

    private static func valueLabel(_ v: Double, field: GameField) -> String {
        switch field {
        case .fgPct, .threePct, .ftPct, .tsPct, .usgPct, .pie:
            let p = v <= 1.0 ? v * 100 : v
            return String(format: "%.0f%%", p)
        case .careerRings, .careerMvp, .careerFinalsMvp, .careerAllNba,
             .careerAllStar, .careerAllDefense, .draftYear, .draftRound,
             .draftPick, .decadeStartYear, .seasonStartYear:
            return "\(Int(v))"
        default:
            return String(format: "%.1f", v)
        }
    }

    private static func fieldNoun(_ field: GameField) -> String {
        switch field {
        case .pts: return "points per game"
        case .reb: return "rebounds per game"
        case .ast: return "assists per game"
        case .stl: return "steals per game"
        case .blk: return "blocks per game"
        case .tov: return "turnovers per game"
        case .fgPct: return "field-goal %"
        case .threePct: return "three-point %"
        case .ftPct: return "free-throw %"
        case .tsPct: return "true-shooting %"
        case .usgPct: return "usage %"
        case .pie: return "PIE"
        case .rating: return "overall rating"
        case .netRating: return "net rating"
        case .salary: return "salary"
        case .careerRings: return "championship rings"
        case .careerMvp: return "MVP awards"
        case .careerFinalsMvp: return "Finals MVPs"
        case .careerAllNba: return "All-NBA selections"
        case .careerAllStar: return "All-Star selections"
        case .careerAllDefense: return "All-Defense selections"
        case .draftPick: return "draft pick number"
        case .draftRound: return "draft round"
        case .draftYear: return "draft year"
        case .age: return "age"
        default: return field.rawValue
        }
    }

    private static func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }
}
