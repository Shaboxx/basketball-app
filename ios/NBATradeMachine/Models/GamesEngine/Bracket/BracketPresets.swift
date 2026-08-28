import Foundation

/// BRACKET presets (spec §33 presets-as-data). Registry card id → the bracket
/// game its Start button launches. Computed `static var` for the same Sendable
/// reason as the roster presets (`GameConstraint` blocks auto-Sendable).
nonisolated enum BracketPresets {

    static let bestPlayerBracketId = "best-player-bracket"   // 16-seed, model-agreement
    static let positionBracketId = "position-bracket"        // 8-seed
    static let quickBracketId = "quick-bracket"              // 4-seed

    static func definition(for gameId: String) -> BracketDefinition? {
        switch gameId {
        case Self.bestPlayerBracketId: return bestPlayerBracket
        case Self.positionBracketId:   return positionBracket
        case Self.quickBracketId:      return quickBracket
        default:                       return nil
        }
    }

    /// 16 top-rated players, seeded 1–16 so the favourites meet late; pick a
    /// champion and see how often you agreed with the model.
    static var bestPlayerBracket: BracketDefinition {
        BracketDefinition(id: Self.bestPlayerBracketId, title: "Best Player Bracket",
                          fieldSize: 16, seedByRating: true,
                          scoring: .modelAgreement)
    }

    /// 8 players, seeded by rating — a shorter bracket, model-agreement scored.
    static var positionBracket: BracketDefinition {
        BracketDefinition(id: Self.positionBracketId, title: "Position Bracket",
                          fieldSize: 8, seedByRating: true,
                          scoring: .modelAgreement)
    }

    /// 4 randomly-drawn players — a fast, purely-subjective bracket (no scoring).
    static var quickBracket: BracketDefinition {
        BracketDefinition(id: Self.quickBracketId, title: "Quick Bracket",
                          fieldSize: 4, seedByRating: false,
                          scoring: .none)
    }
}
