import Foundation

/// Eligibility-rarity scoring (Sol Q2-A), factored OUT of the engine loop so it's
/// swappable without touching `GridEngine`. Score for a cell = 100 divided by the
/// number of DISTINCT pool players who satisfy AND(row, col) — rarer
/// intersections are worth more — clamped to 1...100. This is objective and
/// reproducible (no live-crowd data), measuring true intersection rarity.
///
/// `eligibleCount` is ALSO the always-solvable generation gate the engine calls
/// to verify every one of the 9 cells has ≥1 (or ≥ `minCellAnswers`) answers.
nonisolated enum GridRarityScorer {

    /// Distinct pool players satisfying AND(row, col). Pure O(pool).
    static func eligibleCount(row: GridAxis, col: GridAxis,
                              pool: [HistoricalPlayerEntity]) -> Int {
        pool.reduce(0) { $0 + (($1.satisfies(row: row, col: col)) ? 1 : 0) }
    }

    /// Rarity points for a filled cell: `round(100 / max(count,1)) * scaling`,
    /// clamped to 1...100. `count == 0` is guarded (→ treated as 1 ⇒ 100), though
    /// the engine never fills a 0-answer cell (it isn't presented).
    static func rarity(count: Int, scaling: Double = 1.0) -> Int {
        let safeCount = max(count, 1)
        let raw = (100.0 / Double(safeCount)) * scaling
        let clamped = min(100.0, max(1.0, raw.rounded()))
        return Int(clamped)
    }

    /// Convenience: score a cell directly from the pool.
    static func rarity(row: GridAxis, col: GridAxis,
                       pool: [HistoricalPlayerEntity], scaling: Double = 1.0) -> Int {
        rarity(count: eligibleCount(row: row, col: col, pool: pool), scaling: scaling)
    }
}
