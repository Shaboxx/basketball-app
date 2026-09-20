import XCTest
@testable import BasketballOffline

/// Phase 5 T4: the GUESS scoring ladder — fewer clues used = more points,
/// monotonic decreasing, loss = 0, single-clue ladder = 100 on a win.
final class GuessScorerTests: XCTestCase {

    func testLossIsZero() {
        XCTAssertEqual(GuessScorer.score(won: false, cluesUsed: 1, maxClues: 6), 0)
        XCTAssertEqual(GuessScorer.score(won: false, cluesUsed: 6, maxClues: 6), 0)
    }

    func testFirstClueIsTopOfLadder() {
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 1, maxClues: 6), 100)
    }

    func testLastClueIsBottomRung() {
        // 1 rung of 6 → ~17.
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 6, maxClues: 6), 17)
    }

    func testMonotonicDecreasingInCluesUsed() {
        var prev = Int.max
        for used in 1...6 {
            let s = GuessScorer.score(won: true, cluesUsed: used, maxClues: 6)
            XCTAssertLessThan(s, prev, "score should decrease as clues increase (used=\(used))")
            prev = s
        }
    }

    func testSingleClueLadderScores100() {
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 1, maxClues: 1), 100)
    }

    func testCluesUsedClampedDefensively() {
        // Out-of-range cluesUsed clamps into 1…maxClues (decoded-state defense).
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 0, maxClues: 4),
                       GuessScorer.score(won: true, cluesUsed: 1, maxClues: 4))
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 99, maxClues: 4),
                       GuessScorer.score(won: true, cluesUsed: 4, maxClues: 4))
    }

    func testZeroMaxCluesIsZero() {
        XCTAssertEqual(GuessScorer.score(won: true, cluesUsed: 1, maxClues: 0), 0)
    }
}
