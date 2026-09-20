import XCTest
@testable import BasketballOffline

/// Phase 5 T3/T4: GUESS engine — seeded target + ordered clues, replay identity,
/// thin-pool tolerance (skip absent clue fields), reveal/guess transitions, typed
/// errors, and the scoring ladder.
final class GuessEngineTests: XCTestCase {

    /// A pool of historical-shaped entities with content fields set.
    private func pool() -> [GameEntityRecord] {
        (0..<12).map { i in
            GameEntityRecord(id: "p\(i)", name: "Player \(i)", team: "T\(i % 4)",
                             position: ["GUARD", "WING", "BIG"][i % 3],
                             salary: nil, rating: Double(90 - i),
                             decadeStartYear: 1990 + (i % 3) * 10,
                             careerRings: i % 4,
                             pts: Double(30 - i), reb: Double(5 + i), ast: Double(4 + i),
                             seasonLabel: "199\(i % 9)-9\(i % 9)")
        }
    }

    private func def(_ fields: [GameField] = [.decadeStartYear, .position, .team, .pts, .reb, .ast],
                     maxClues: Int = 6, candidatePoolSize: Int = 12) -> GuessDefinition {
        GuessDefinition(id: "t", title: "T", poolSource: .historical(.allEligible),
                        config: GuessConfig(clueFields: fields,
                                            candidatePoolSize: candidatePoolSize,
                                            maxClues: maxClues))
    }

    // MARK: - Initialize

    func testInitializeSeedsTargetAndOpensOneClue() throws {
        let s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 5)
        XCTAssertEqual(s.revealedCount, 1)
        XCTAssertEqual(s.status, .active)
        XCTAssertNotNil(s.target)
        XCTAssertFalse(s.orderedClues.isEmpty)
        XCTAssertLessThanOrEqual(s.orderedClues.count, 6)
    }

    func testSameSeedIdenticalTargetAndClues() throws {
        let a = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 42)
        let b = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 42)
        XCTAssertEqual(a.targetId, b.targetId)
        XCTAssertEqual(a.orderedClues, b.orderedClues)
    }

    func testCluesOnlyFromFieldsPresentOnTarget() throws {
        // Only `pts` and `team` present on the pool; ask for salary (absent) too.
        let thin = [GameEntityRecord(id: "a", name: "A", team: "AAA", position: "GUARD",
                                     salary: nil, rating: 50, pts: 20)]
        let d = def([.salary, .pts, .team], maxClues: 3, candidatePoolSize: 1)
        let s = try GuessEngine.initialize(definition: d, pool: thin, seed: 1)
        // salary is absent → skipped; pts + team remain.
        XCTAssertEqual(s.orderedClues.map(\.field), [.pts, .team])
    }

    func testInitializeThrowsOnEmptyPool() {
        XCTAssertThrowsError(try GuessEngine.initialize(definition: def(), pool: [], seed: 1)) {
            XCTAssertEqual($0 as? GuessError, .emptyPool)
        }
    }

    func testInitializeThrowsWhenNoCluesResolvable() {
        // Target has none of the requested clue fields.
        let e = [GameEntityRecord(id: "a", name: "A", team: "AAA", position: "GUARD",
                                  salary: nil, rating: 50)]
        let d = def([.pts, .reb, .ast], maxClues: 3, candidatePoolSize: 1)
        XCTAssertThrowsError(try GuessEngine.initialize(definition: d, pool: e, seed: 1)) {
            XCTAssertEqual($0 as? GuessError, .noClues)
        }
    }

    func testCluesClampedToMaxClues() throws {
        let d = def([.decadeStartYear, .position, .team, .pts, .reb, .ast], maxClues: 2)
        let s = try GuessEngine.initialize(definition: d, pool: pool(), seed: 3)
        XCTAssertEqual(s.orderedClues.count, 2)
    }

    // MARK: - Reveal

    func testRevealAdvancesAndNeverExceeds() throws {
        var s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 7)
        let total = s.orderedClues.count
        while s.revealedCount < total {
            s = try GuessEngine.revealNextClue(s)
        }
        XCTAssertEqual(s.revealedCount, total)
        XCTAssertThrowsError(try GuessEngine.revealNextClue(s)) {
            XCTAssertEqual($0 as? GuessError, .noMoreClues)
        }
    }

    // MARK: - Guess

    func testCorrectGuessWinsWithLadderScore() throws {
        let s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 9)
        let won = try GuessEngine.guess(s, subjectId: s.targetId)
        XCTAssertEqual(won.status, .won)
        XCTAssertEqual(won.lastGuessCorrect, true)
        // Guessed on the first clue → top of the ladder.
        XCTAssertEqual(GuessEngine.score(won),
                       GuessScorer.score(won: true, cluesUsed: 1, maxClues: s.orderedClues.count))
        XCTAssertGreaterThan(GuessEngine.score(won), 0)
    }

    func testWrongGuessAdvancesClueAndDecrements() throws {
        let s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 11)
        let wrongId = s.pool.first { $0.id != s.targetId }!.id
        let after = try GuessEngine.guess(s, subjectId: wrongId)
        XCTAssertEqual(after.lastGuessCorrect, false)
        XCTAssertEqual(after.guessesRemaining, s.guessesRemaining - 1)
        XCTAssertEqual(after.status, .active)
        XCTAssertEqual(after.revealedCount, 2)   // auto-advanced a clue
    }

    func testRunningOutOfGuessesLoses() throws {
        var s = try GuessEngine.initialize(definition: def(maxClues: 3), pool: pool(), seed: 13)
        let wrong = { s.pool.first { $0.id != s.targetId }!.id }
        for _ in 0..<s.guessesRemaining { s = try GuessEngine.guess(s, subjectId: wrong()) }
        XCTAssertEqual(s.status, .lost)
        XCTAssertEqual(GuessEngine.score(s), 0)
        // All clues revealed on a loss (to show the answer).
        XCTAssertEqual(s.revealedCount, s.orderedClues.count)
    }

    func testGuessAfterFinishedThrows() throws {
        let s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 17)
        let won = try GuessEngine.guess(s, subjectId: s.targetId)
        XCTAssertThrowsError(try GuessEngine.guess(won, subjectId: won.targetId)) {
            XCTAssertEqual($0 as? GuessError, .alreadyFinished)
        }
    }

    func testGuessUnknownEntityThrows() throws {
        let s = try GuessEngine.initialize(definition: def(), pool: pool(), seed: 19)
        XCTAssertThrowsError(try GuessEngine.guess(s, subjectId: "not-in-pool")) {
            XCTAssertEqual($0 as? GuessError, .unknownEntity)
        }
    }

    func testDedupsPoolById() throws {
        let dup = pool() + [pool()[0]]
        let s = try GuessEngine.initialize(definition: def(), pool: dup, seed: 1)
        XCTAssertEqual(Set(s.pool.map(\.id)).count, s.pool.count)
    }
}
