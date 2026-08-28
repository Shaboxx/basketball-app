import Foundation

/// How a finished bracket is scored (spec §20 Phase-8 BRACKET). `none` = a pure
/// subjective champion (no objective judgement — the honest default for a
/// "who's better" tournament). `modelAgreement` counts, offline and with no live
/// results needed, how many matchups the human's advanced winner matched the
/// higher-rating entity of that matchup — an objective accuracy signal.
nonisolated enum BracketScoring: String, Codable, Equatable {
    case none
    case modelAgreement
}

/// A BRACKET game definition (self-contained; NOT the roster `GameDefinition`).
/// BRACKET is a genuinely NEW engine (Sol §108): advancing a winner changes
/// future matchups → elimination rounds → a tournament-progression LOOP, distinct
/// from COMPARE's independent pairwise streak.
///
/// `fieldSize` must be a power of two in {4, 8, 16} — a clean single-elimination
/// bracket. `seedByRating` seeds the field by rating (1-vs-N, 2-vs-(N-1), …) so
/// the strongest entities meet late; false uses the seeded RNG for a random
/// bracket. `entityConstraints` filters the pool exactly like a roster
/// definition's does.
nonisolated struct BracketDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let fieldSize: Int                       // ∈ {4, 8, 16}
    let seedByRating: Bool
    let entityConstraints: [GameConstraint]  // pool filter
    let scoring: BracketScoring

    init(id: String, title: String, fieldSize: Int, seedByRating: Bool,
         entityConstraints: [GameConstraint] = [], scoring: BracketScoring = .none) {
        self.id = id
        self.title = title
        self.fieldSize = fieldSize
        self.seedByRating = seedByRating
        self.entityConstraints = entityConstraints
        self.scoring = scoring
    }
}
