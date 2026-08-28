import Foundation

/// QUIZ presets (spec §33 presets-as-data). Registry card id → the QUIZ game its
/// Start button launches. Computed `static var` to match the family pattern.
nonisolated enum QuizPresets {

    static let nbaTriviaId = "nba-trivia-quiz"   // current pool
    static let allTimeId = "all-time-quiz"       // historical pool

    static let allIds: [String] = [nbaTriviaId, allTimeId]

    static func definition(for gameId: String) -> QuizDefinition? {
        switch gameId {
        case Self.nbaTriviaId: return nbaTrivia
        case Self.allTimeId:   return allTimeQuiz
        default:               return nil
        }
    }

    /// Current-player trivia. The live pool only carries team/position/rating/
    /// salary, so questions are superlatives + head-to-head over rating & salary.
    static var nbaTrivia: QuizDefinition {
        QuizDefinition(
            id: Self.nbaTriviaId,
            title: "NBA Trivia Quiz",
            poolSource: .current,
            config: QuizConfig(
                templates: [
                    .superlative(field: .rating, higherIsBetter: true),
                    .higherField(field: .rating, higherIsBetter: true),
                    .superlative(field: .salary, higherIsBetter: true),
                    .higherField(field: .salary, higherIsBetter: true),
                ],
                questionCount: 8,
                choiceCount: 4,
                candidatePoolSize: 60))
    }

    /// All-time trivia over the historical player-season pool: box-stat
    /// superlatives, ring/MVP counts, which-season, and head-to-head comparisons.
    static var allTimeQuiz: QuizDefinition {
        QuizDefinition(
            id: Self.allTimeId,
            title: "All-Time Quiz",
            poolSource: .historical(HistoricalFilter(minRating: 70)),
            config: QuizConfig(
                templates: [
                    .superlative(field: .pts, higherIsBetter: true),
                    .superlative(field: .reb, higherIsBetter: true),
                    .superlative(field: .ast, higherIsBetter: true),
                    .attributeLookup(field: .careerRings),
                    .higherField(field: .pts, higherIsBetter: true),
                ],
                questionCount: 8,
                choiceCount: 4,
                candidatePoolSize: 200))
    }
}
