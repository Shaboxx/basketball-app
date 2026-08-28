import Foundation

/// Pure scorer for a GUESS game, factored OUT of the interaction loop (mirrors
/// `ClassificationScorer` / `BracketScorer`) so a future scoring swap never
/// touches the engine.
///
/// The ladder: a correct guess after seeing `cluesUsed` clues (1…maxClues) earns
/// points that DECREASE monotonically as more clues are needed. Guessing on the
/// first clue is worth `maxClues` "rungs"; the last clue is worth 1. Rungs are
/// scaled to a 0…100 band so scores read the same regardless of how many clues a
/// preset uses. A loss (never guessed correctly) scores 0.
nonisolated enum GuessScorer {

    /// Score a finished GUESS.
    /// - `won`: did the player guess correctly at all?
    /// - `cluesUsed`: how many clues were revealed at the moment of the winning
    ///   guess (1-based; guessing on the very first clue = 1).
    /// - `maxClues`: the ladder height (config.maxClues, already clamped to the
    ///   target's usable clue count).
    static func score(won: Bool, cluesUsed: Int, maxClues: Int) -> Int {
        guard won, maxClues > 0 else { return 0 }
        // Clamp cluesUsed into 1…maxClues (defensive against a decoded state).
        let used = min(max(cluesUsed, 1), maxClues)
        // Rungs remaining, inclusive: used==1 → maxClues rungs; used==maxClues → 1.
        let rungs = maxClues - used + 1
        // Scale to 0…100. A single-clue ladder (maxClues==1) always scores 100 on
        // a win (the only possible rung).
        return Int((Double(rungs) / Double(maxClues) * 100).rounded())
    }
}
