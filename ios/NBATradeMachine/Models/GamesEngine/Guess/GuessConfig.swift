import Foundation

// GUESS/QUIZ/SURVIVOR reuse the Phase-4.5 `GamePoolSource` (`.current` /
// `.historical(HistoricalFilter)`) so the launching views branch on the SAME pool
// source the roster games do — no parallel content-source type.

/// A GUESS game's configuration. A mystery entity is drawn (seeded) from the top
/// `candidatePoolSize` entities by rating; then an ORDERED sequence of clue
/// fields is revealed. Fewer clues used before a correct guess = more points
/// (see `GuessScorer`). `maxClues` caps how many are ever shown (also the number
/// of guesses allowed — one per revealed clue).
nonisolated struct GuessConfig: Codable, Equatable {
    /// The ordered content fields to reveal as clues (broad → specific by
    /// convention, e.g. decade → team → box line → award). A clue whose field is
    /// absent on the chosen target is skipped at initialize (thin-pool tolerance).
    let clueFields: [GameField]
    /// The candidate set the mystery target is drawn from: the top-N entities by
    /// rating (recognizable). Clamped to the pool size.
    let candidatePoolSize: Int
    /// Max clues revealed (and max guesses). The ladder in `GuessScorer` keys off
    /// this. Clamped to the number of usable clue fields on the target.
    let maxClues: Int

    init(clueFields: [GameField], candidatePoolSize: Int, maxClues: Int) {
        self.clueFields = clueFields
        self.candidatePoolSize = candidatePoolSize
        self.maxClues = maxClues
    }
}

/// A GUESS game (self-contained; NOT the roster `GameDefinition`).
nonisolated struct GuessDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let poolSource: GamePoolSource
    let config: GuessConfig

    init(id: String, title: String, poolSource: GamePoolSource, config: GuessConfig) {
        self.id = id
        self.title = title
        self.poolSource = poolSource
        self.config = config
    }
}
