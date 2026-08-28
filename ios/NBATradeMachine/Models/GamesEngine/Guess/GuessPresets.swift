import Foundation

/// GUESS presets (spec §33 presets-as-data). Registry card id → the GUESS game
/// its Start button launches. Computed `static var` for Sendability (nested
/// `HistoricalFilter` value is Sendable; kept `var` to match the family pattern).
nonisolated enum GuessPresets {

    // Ids — each MUST match a `DraftGameRegistry` card id.
    static let nbaDraftGuessId = "nba-draft-guess"          // existing seasonal card, now GUESS
    static let guessTheSeasonId = "guess-the-season"        // historical player-season
    static let guessCurrentId = "guess-the-current-player"  // current active player

    static let allIds: [String] = [nbaDraftGuessId, guessTheSeasonId, guessCurrentId]

    static func definition(for gameId: String) -> GuessDefinition? {
        switch gameId {
        case Self.nbaDraftGuessId:  return nbaDraftGuess
        case Self.guessTheSeasonId: return guessTheSeason
        case Self.guessCurrentId:   return guessCurrentPlayer
        default:                    return nil
        }
    }

    /// The seasonal NBA Draft Guess card, now playable: guess a mystery historical
    /// standout from broadening clues (decade → team → box line → awards). Draws
    /// from the recognizable top of the all-time eligible pool.
    static var nbaDraftGuess: GuessDefinition {
        GuessDefinition(
            id: Self.nbaDraftGuessId,
            title: "NBA Draft Guess",
            poolSource: .historical(HistoricalFilter(minRating: 70)),
            config: GuessConfig(
                clueFields: [.decadeStartYear, .position, .careerRings, .pts, .team, .careerAllStar],
                candidatePoolSize: 120,
                maxClues: 6))
    }

    /// Guess the mystery player-SEASON from broadening clues over the all-time
    /// eligible historical pool.
    static var guessTheSeason: GuessDefinition {
        GuessDefinition(
            id: Self.guessTheSeasonId,
            title: "Guess the Season",
            poolSource: .historical(HistoricalFilter(minRating: 68)),
            config: GuessConfig(
                clueFields: [.decadeStartYear, .position, .team, .reb, .ast, .pts],
                candidatePoolSize: 150,
                maxClues: 6))
    }

    /// Guess a mystery ACTIVE player from clues about their current team, position,
    /// and rating. Current pool has no historical stat fields, so the clue set is
    /// gated to fields `GamePoolBuilder` populates (team/position/rating/salary).
    static var guessCurrentPlayer: GuessDefinition {
        GuessDefinition(
            id: Self.guessCurrentId,
            title: "Guess the Current Player",
            poolSource: .current,
            config: GuessConfig(
                clueFields: [.position, .rating, .salary, .team],
                candidatePoolSize: 80,
                maxClues: 4))
    }
}
