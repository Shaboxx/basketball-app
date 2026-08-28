import Foundation

/// A QUIZ template. Each kind is a pure seeded generator over the pool (see
/// `QuizEngine`). New quiz shapes become new cases here; the engine loop never
/// changes.
///
/// - `superlative(field, higherIsBetter)`: "Who has the most/least <field>?" —
///   the true argmax/argmin over a seeded sample; distractors are other sampled
///   entities.
/// - `attributeLookup(field)`: "What was <player>'s <field>?" — the true numeric
///   value; distractors are plausible nearby numbers.
/// - `whichSeason`: "Which season did <player-season> belong to?" — the true
///   season label; distractors are other seasons in the pool.
/// - `higherField(field, higherIsBetter)`: "Which player had the higher/lower
///   <field>?" — a two-choice comparison drawn from the pool.
nonisolated enum QuizTemplateKind: Codable, Equatable {
    case superlative(field: GameField, higherIsBetter: Bool)
    case attributeLookup(field: GameField)
    case whichSeason
    case higherField(field: GameField, higherIsBetter: Bool)
}

/// A QUIZ game's configuration. `questionCount` template questions are built up
/// front from `templates` (cycled if fewer templates than questions). `choiceCount`
/// = total options per question (1 answer + choiceCount-1 seeded distractors).
/// `candidatePoolSize` bounds the argmax/sampling scan (recognizable subjects).
nonisolated struct QuizConfig: Codable, Equatable {
    let templates: [QuizTemplateKind]
    let questionCount: Int
    let choiceCount: Int
    let candidatePoolSize: Int

    init(templates: [QuizTemplateKind], questionCount: Int,
         choiceCount: Int, candidatePoolSize: Int) {
        self.templates = templates
        self.questionCount = questionCount
        self.choiceCount = choiceCount
        self.candidatePoolSize = candidatePoolSize
    }
}

/// A generated QUIZ question: a stem, the ordered choice labels, and the index of
/// the correct one. All are frozen at `initialize` (seeded), so replay is exact.
/// `subjectIds` mirrors `choices` positionally where a choice corresponds to a
/// pool entity (used by the view for nothing beyond debugging; the answer is the
/// index).
nonisolated struct QuizQuestion: Codable, Equatable, Identifiable {
    let id: Int                 // 0-based ordinal within the quiz
    let stem: String
    let choices: [String]       // display labels
    let correctIndex: Int

    init(id: Int, stem: String, choices: [String], correctIndex: Int) {
        self.id = id
        self.stem = stem
        self.choices = choices
        self.correctIndex = correctIndex
    }
}

/// A QUIZ game (self-contained; NOT the roster `GameDefinition`).
nonisolated struct QuizDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let poolSource: GamePoolSource
    let config: QuizConfig

    init(id: String, title: String, poolSource: GamePoolSource, config: QuizConfig) {
        self.id = id
        self.title = title
        self.poolSource = poolSource
        self.config = config
    }
}
