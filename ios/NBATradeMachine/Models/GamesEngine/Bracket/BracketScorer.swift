import Foundation

/// A finished BRACKET (spec §25): champion + optional objective accuracy. Scoring
/// is factored OUT of the loop (mirrors `ClassificationScorer` / `GameResult`) so
/// a future evaluator swap never touches the engine.
nonisolated struct BracketResult: Codable, Equatable {
    let champion: GameEntityRecord?      // nil until the final is decided
    let modelAgreementCount: Int?        // nil when scoring == .none
    let totalMatchups: Int
}

/// Pure nonisolated bracket scorer. `modelAgreement` replays each decided matchup
/// and counts the ones whose picked winner is the higher-rating side (rating
/// ties count as agreement — the pick can't be "wrong" when the two are equal).
nonisolated enum BracketScorer {

    static func buildResult(_ state: BracketState) -> BracketResult {
        let total = BracketEngine.totalMatchups(fieldSize: state.definition.fieldSize)
        let champion: GameEntityRecord? = {
            guard state.status == .complete, let last = state.picks.last else { return nil }
            return state.entity(last)
        }()

        let agreement: Int?
        switch state.definition.scoring {
        case .none:
            agreement = nil
        case .modelAgreement:
            agreement = modelAgreementCount(state)
        }

        return BracketResult(champion: champion,
                             modelAgreementCount: agreement,
                             totalMatchups: total)
    }

    /// Count decided matchups where the human's pick matched the higher-rating
    /// side. Replays the bracket round-by-round using the recorded picks so each
    /// matchup's two actual sides are known (a later round's sides depend on
    /// earlier picks). Undecided matchups are skipped.
    static func modelAgreementCount(_ state: BracketState) -> Int {
        let fieldSize = state.definition.fieldSize
        let totalRounds = rounds(fieldSize: fieldSize)
        var agree = 0
        for round in 0..<totalRounds {
            let field = BracketEngine.participants(state, round: round)
            let (start, count) = BracketEngine.pickRange(fieldSize: fieldSize, round: round)
            for m in 0..<count {
                let pickIndex = start + m
                guard pickIndex < state.picks.count else { continue }
                let a = 2 * m, b = a + 1
                guard field.indices.contains(a), field.indices.contains(b) else { continue }
                let left = field[a], right = field[b]
                let pickedId = state.picks[pickIndex]
                // Higher-rating side (ties → left, and a tie can't be "wrong").
                let modelId = left.rating >= right.rating ? left.id : right.id
                if left.rating == right.rating {
                    agree += 1        // equal ratings: any legal pick agrees
                } else if pickedId == modelId {
                    agree += 1
                }
            }
        }
        return agree
    }

    /// Number of rounds for a field size (log2). {4→2, 8→3, 16→4}.
    private static func rounds(fieldSize: Int) -> Int {
        var n = fieldSize, r = 0
        while n > 1 { n /= 2; r += 1 }
        return r
    }
}
