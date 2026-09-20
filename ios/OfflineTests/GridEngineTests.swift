import XCTest
@testable import BasketballOffline

/// Phase-6 T4: always-solvable generation (every cell ≥1 answer), header reroll on
/// an unsolvable draw, infeasible-throw past the budget, determinism, and
/// submitAnswer validation/scoring.
final class GridEngineTests: XCTestCase {

    private func player(id: String, franchises: Set<String>, decades: Set<Int>,
                        families: Set<String> = ["GUARD"], rings: Int = 0,
                        allNba: Int = 0, allStar: Int = 0) -> HistoricalPlayerEntity {
        HistoricalPlayerEntity(id: id, name: "P\(id)", appSlug: nil,
                               franchises: franchises, decades: decades, families: families,
                               careerRings: rings, careerMvp: 0, careerAllNba: allNba,
                               careerAllStar: allStar, careerAllDefense: 0, bestRating: 70)
    }

    /// A DENSE all-time pool: each player belongs to ALL three test franchises AND
    /// ALL three decades AND all families/awards → every franchise×decade cell has
    /// many answers, so any header draw is solvable. Guarantees generation succeeds.
    private func densePool(count: Int = 12) -> [HistoricalPlayerEntity] {
        (0..<count).map {
            player(id: "\($0)", franchises: ["LAL", "BOS", "MIA"],
                   decades: [1990, 2000, 2010], families: ["GUARD", "WING", "BIG"],
                   rings: 1, allNba: 1, allStar: 1)
        }
    }

    private let mixedDef = GridDefinition(id: "immaculate-grid", title: "Grid",
                                          axisFamilies: [.franchise, .decade, .positionFamily, .award])

    func testGeneratesFullySolvableGrid() throws {
        let state = try GridEngine.initialize(definition: mixedDef, pool: densePool(), seed: 42)
        XCTAssertEqual(state.rowAxes.count, 3)
        XCTAssertEqual(state.colAxes.count, 3)
        // Every one of the 9 cells has ≥1 answer.
        XCTAssertTrue(GridEngine.allCellsSolvable(rowAxes: state.rowAxes, colAxes: state.colAxes,
                                                  pool: state.pool, minAnswers: 1))
        for r in state.rowAxes {
            for c in state.colAxes {
                XCTAssertGreaterThanOrEqual(
                    GridRarityScorer.eligibleCount(row: r, col: c, pool: state.pool), 1)
            }
        }
    }

    func testDeterministicHeadersForSameSeed() throws {
        let a = try GridEngine.initialize(definition: mixedDef, pool: densePool(), seed: 7)
        let b = try GridEngine.initialize(definition: mixedDef, pool: densePool(), seed: 7)
        XCTAssertEqual(a.rowAxes, b.rowAxes)
        XCTAssertEqual(a.colAxes, b.colAxes)
    }

    func testThrowsInfeasibleWhenTooFewAxes() {
        // Only one franchise present → not enough distinct axes for 6 headers.
        let pool = [player(id: "1", franchises: ["LAL"], decades: [2000])]
        let franchiseDef = GridDefinition(id: "franchise-grid", title: "F",
                                          axisFamilies: [.franchise])
        XCTAssertThrowsError(try GridEngine.initialize(definition: franchiseDef, pool: pool, seed: 1)) {
            XCTAssertEqual($0 as? GridError, .infeasibleGrid)
        }
    }

    func testThrowsInfeasibleWhenNoSolvableDraw() {
        // Six franchises, but each player belongs to exactly one → EVERY
        // franchise×franchise off-diagonal cell has 0 answers, so no all-solvable
        // 3×3 draw exists (diagonal cells would need row==col, which the shuffle
        // never yields for 3 distinct headers). Must throw, not loop.
        let franchises = ["AA", "BB", "CC", "DD", "EE", "FF"]
        let pool = franchises.map { player(id: $0, franchises: [$0], decades: [2000]) }
        let franchiseDef = GridDefinition(id: "franchise-grid", title: "F",
                                          axisFamilies: [.franchise])
        XCTAssertThrowsError(try GridEngine.initialize(definition: franchiseDef, pool: pool, seed: 3)) {
            XCTAssertEqual($0 as? GridError, .infeasibleGrid)
        }
    }

    func testSubmitAnswerScoresAndFills() throws {
        // 12 distinct players so a 9-distinct global solution (Hall's condition)
        // exists; the score is computed from the drawn cell's live eligible count
        // (not a hardcoded rarity), so the exact count doesn't matter here.
        let pool = [
            player(id: "1", franchises: ["LAL", "BOS", "MIA"], decades: [1990, 2000, 2010]),
            player(id: "2", franchises: ["LAL", "BOS", "MIA"], decades: [1990, 2000, 2010]),
        ] + densePool(count: 10)
        let state = try GridEngine.initialize(definition: mixedDef, pool: pool, seed: 5)
        // Pick a real cell + a player who satisfies it.
        let cell = GridCell(row: 0, col: 0)
        let row = state.rowAxes[0], col = state.colAxes[0]
        let answerer = state.pool.first { $0.satisfies(row: row, col: col) }!
        let count = GridRarityScorer.eligibleCount(row: row, col: col, pool: state.pool)
        let next = try GridEngine.submitAnswer(state, cell: cell, playerId: answerer.id)
        XCTAssertEqual(next.cellFills[cell]?.playerId, answerer.id)
        XCTAssertEqual(next.score, GridRarityScorer.rarity(count: count))
        XCTAssertTrue(next.usedPlayerIds.contains(answerer.id))
    }

    func testSubmitRejectsInvalidPlayer() throws {
        let state = try GridEngine.initialize(definition: mixedDef, pool: densePool(), seed: 5)
        // Unknown id.
        XCTAssertThrowsError(try GridEngine.submitAnswer(state, cell: GridCell(row: 0, col: 0),
                                                         playerId: "nope")) {
            XCTAssertEqual($0 as? GridError, .unknownPlayer)
        }
    }

    func testSubmitRejectsNonSatisfying() throws {
        // A player who fits nothing in this pool's axes.
        let outsider = player(id: "z", franchises: ["ZZZ"], decades: [1970])
        let state = try GridEngine.initialize(definition: mixedDef,
                                              pool: densePool() + [outsider], seed: 9)
        // The outsider satisfies no LAL/BOS/MIA + 1990/2000/2010 cell.
        let cell = GridCell(row: 0, col: 0)
        XCTAssertThrowsError(try GridEngine.submitAnswer(state, cell: cell, playerId: "z")) {
            XCTAssertEqual($0 as? GridError, .doesNotSatisfy)
        }
    }

    func testSubmitRejectsReuseAndFilledCell() throws {
        let state = try GridEngine.initialize(definition: mixedDef, pool: densePool(), seed: 11)
        let a = GridCell(row: 0, col: 0), b = GridCell(row: 1, col: 1)
        let p = state.pool.first { $0.satisfies(row: state.rowAxes[0], col: state.colAxes[0]) }!
        let s1 = try GridEngine.submitAnswer(state, cell: a, playerId: p.id)
        // Same player again in another (valid) cell → alreadyUsed.
        XCTAssertThrowsError(try GridEngine.submitAnswer(s1, cell: b, playerId: p.id)) {
            XCTAssertEqual($0 as? GridError, .alreadyUsed)
        }
        // Re-filling cell a with a different player → cellFilled.
        let other = state.pool.first { $0.id != p.id &&
            $0.satisfies(row: state.rowAxes[0], col: state.colAxes[0]) }!
        XCTAssertThrowsError(try GridEngine.submitAnswer(s1, cell: a, playerId: other.id)) {
            XCTAssertEqual($0 as? GridError, .cellFilled)
        }
    }

    /// FIX 1 (Hall's condition): a pool where all 9 cells are individually nonempty
    /// but the cells collectively share FEWER than 9 distinct eligible players must
    /// NEVER be returned playable — initialize either rerolls to a grid with a
    /// size-9 matching or throws `.infeasibleGrid`. Here only 3 identical players fit
    /// every cell (they all belong to LAL/BOS/MIA × 1990/2000/2010), so per-cell
    /// solvability holds everywhere but no 9-distinct system exists.
    func testRejectsGridLackingGlobalDistinctSolution() {
        let sharedPool = (0..<3).map {
            player(id: "shared\($0)", franchises: ["LAL", "BOS", "MIA"],
                   decades: [1990, 2000, 2010], families: ["GUARD", "WING", "BIG"],
                   rings: 1, allNba: 1, allStar: 1)
        }
        // Only franchise/decade axes → every drawn header is one of LAL/BOS/MIA or
        // 1990/2000/2010, all satisfied by the 3 shared players and NOBODY else.
        let def = GridDefinition(id: "shared-grid", title: "S",
                                 axisFamilies: [.franchise, .decade])
        // Across many seeds, initialize must NEVER hand back a grid whose 9 cells
        // lack a size-9 matching (it should throw .infeasibleGrid for this pool).
        for seed in UInt64(0)..<40 {
            do {
                let state = try GridEngine.initialize(definition: def, pool: sharedPool, seed: seed)
                XCTAssertTrue(
                    GridEngine.gridHasDistinctSolution(rowAxes: state.rowAxes,
                                                       colAxes: state.colAxes,
                                                       pool: state.pool),
                    "returned an unsolvable grid (no 9-distinct matching) for seed \(seed)")
            } catch {
                XCTAssertEqual(error as? GridError, .infeasibleGrid)
            }
        }
    }

    /// FIX 1: the matching helper agrees with hand-computed cases. A dense pool of 9+
    /// players each satisfying every cell HAS a perfect matching; a 3-player shared
    /// pool over a 3×3 does NOT.
    func testGridHasDistinctSolutionHelper() {
        let rows: [GridAxis] = [.franchise("LAL"), .franchise("BOS"), .franchise("MIA")]
        let cols: [GridAxis] = [.decade(1990), .decade(2000), .decade(2010)]
        let dense = densePool(count: 9)
        XCTAssertTrue(GridEngine.gridHasDistinctSolution(rowAxes: rows, colAxes: cols, pool: dense))
        let shared = densePool(count: 3)   // only 3 distinct players fit all 9 cells
        XCTAssertFalse(GridEngine.gridHasDistinctSolution(rowAxes: rows, colAxes: cols, pool: shared))
    }

    func testCompletesWhenAllCellsFilled() throws {
        let state = try GridEngine.initialize(definition: mixedDef, pool: densePool(count: 20), seed: 13)
        var s = state
        var idx = 0
        let ids = s.pool.map { $0.id }
        for r in 0..<3 {
            for c in 0..<3 {
                let cell = GridCell(row: r, col: c)
                // densePool players satisfy every cell → pick the next unused id.
                let pid = ids[idx]; idx += 1
                s = try GridEngine.submitAnswer(s, cell: cell, playerId: pid)
            }
        }
        XCTAssertEqual(s.status, .complete)
        XCTAssertEqual(s.cellFills.count, 9)
        // Every cell in the dense pool has 20 answers → rarity 100/20 = 5 each → 45.
        XCTAssertEqual(s.score, 9 * GridRarityScorer.rarity(count: 20))
    }
}
