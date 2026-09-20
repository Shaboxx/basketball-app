import XCTest
@testable import BasketballOffline

/// Phase 5 T9/T10: SURVIVOR predicate partitioning, seeded prompt sequence
/// replay, valid/used/non-satisfying answer transitions, no-reuse accumulation,
/// life loss, skip, and thin-pool tolerance (skip unanswerable prompts).
final class SurvivorEngineTests: XCTestCase {

    /// A pool with ring-holders (even ids) and non-ring guards/bigs.
    private func pool(_ n: Int = 10) -> [GameEntityRecord] {
        (0..<n).map { i in
            GameEntityRecord(id: "p\(i)", name: "P\(i)", team: "T\(i)",
                             position: i % 2 == 0 ? "BIG" : "GUARD",
                             salary: nil, rating: Double(80 - i),
                             careerRings: i % 2 == 0 ? 1 : 0,
                             seasonLabel: "2015-16")
        }
    }

    private func ringPrompt() -> SurvivorPrompt {
        SurvivorPrompt(id: "ring", ask: "Name a champion",
                       predicate: .field(FieldConstraint(field: .careerRings, op: .greaterOrEqual,
                                                         value: .number(1))))
    }
    private func bigPrompt() -> SurvivorPrompt {
        SurvivorPrompt(id: "big", ask: "Name a Big",
                       predicate: .field(FieldConstraint(field: .position, op: .equal,
                                                        value: .string("BIG"))))
    }

    private func def(_ prompts: [SurvivorPrompt], lives: Int = 2) -> SurvivorDefinition {
        SurvivorDefinition(id: "t", title: "T", poolSource: .historical(.allEligible),
                           config: SurvivorConfig(prompts: prompts, lives: lives))
    }

    // MARK: - Predicate partitioning

    func testPredicatePartitionsThePool() {
        let ring = ringPrompt()
        let matches = pool().filter { ring.matches($0) }
        XCTAssertEqual(Set(matches.map(\.id)), ["p0", "p2", "p4", "p6", "p8"])
    }

    // MARK: - Seeded prompt sequence replay

    func testSameSeedSamePromptOrder() throws {
        let d = def([ringPrompt(), bigPrompt()])
        let a = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 21)
        let b = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 21)
        XCTAssertEqual(a.promptOrder, b.promptOrder)
        XCTAssertEqual(a.currentPrompt?.id, b.currentPrompt?.id)
    }

    // MARK: - Initialize guards

    func testInitializeThrowsOnNoPrompts() {
        let d = def([])
        XCTAssertThrowsError(try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)) {
            XCTAssertEqual($0 as? SurvivorError, .noPrompts)
        }
    }

    func testInitializeThrowsOnEmptyPool() {
        let d = def([ringPrompt()])
        XCTAssertThrowsError(try SurvivorEngine.initialize(definition: d, pool: [], seed: 1)) {
            XCTAssertEqual($0 as? SurvivorError, .emptyPool)
        }
    }

    // MARK: - Submit transitions

    func testValidUnusedSatisfyingAdvancesAndStreaks() throws {
        let d = def([ringPrompt()])
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        let ringHolder = s.pool.first { ($0.careerRings ?? 0) >= 1 }!.id
        s = try SurvivorEngine.submitAnswer(s, subjectId: ringHolder)
        XCTAssertEqual(s.streak, 1)
        XCTAssertTrue(s.usedIds.contains(ringHolder))
        XCTAssertEqual(s.lastAnswerCorrect, true)
        XCTAssertEqual(s.status, .playing)
    }

    func testReusingIdThrowsAlreadyUsedNoLifeLost() throws {
        let d = def([ringPrompt()])
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        let ringHolder = s.pool.first { ($0.careerRings ?? 0) >= 1 }!.id
        s = try SurvivorEngine.submitAnswer(s, subjectId: ringHolder)
        let livesBefore = s.livesRemaining
        XCTAssertThrowsError(try SurvivorEngine.submitAnswer(s, subjectId: ringHolder)) {
            XCTAssertEqual($0 as? SurvivorError, .alreadyUsed)
        }
        XCTAssertEqual(s.livesRemaining, livesBefore)   // no penalty on an illegal move
    }

    func testNonSatisfyingLosesALife() throws {
        let d = def([ringPrompt()], lives: 2)
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        let nonRing = s.pool.first { ($0.careerRings ?? 0) == 0 }!.id
        s = try SurvivorEngine.submitAnswer(s, subjectId: nonRing)
        XCTAssertEqual(s.livesRemaining, 1)
        XCTAssertEqual(s.lastAnswerCorrect, false)
        XCTAssertEqual(s.status, .playing)
        XCTAssertFalse(s.usedIds.contains(nonRing))   // a wrong answer doesn't consume
    }

    func testRunningOutOfLivesLoses() throws {
        let d = def([ringPrompt()], lives: 1)
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        let nonRing = s.pool.first { ($0.careerRings ?? 0) == 0 }!.id
        s = try SurvivorEngine.submitAnswer(s, subjectId: nonRing)
        XCTAssertEqual(s.status, .lost)
    }

    func testUnknownEntityThrows() throws {
        let d = def([ringPrompt()])
        let s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        XCTAssertThrowsError(try SurvivorEngine.submitAnswer(s, subjectId: "nope")) {
            XCTAssertEqual($0 as? SurvivorError, .unknownEntity)
        }
    }

    func testUsedIdsAccumulateAcrossPrompts() throws {
        let d = def([ringPrompt(), bigPrompt()])
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        // p0 is a BIG with a ring → satisfies whichever prompt is first.
        let both = s.pool.first { ($0.careerRings ?? 0) >= 1 && $0.position == "BIG" }!.id
        s = try SurvivorEngine.submitAnswer(s, subjectId: both)
        XCTAssertEqual(s.usedIds.count, 1)
        // Now answer the next prompt with a DIFFERENT valid entity.
        if let prompt = s.currentPrompt,
           let other = s.pool.first(where: { !s.usedIds.contains($0.id) && prompt.matches($0) }) {
            s = try SurvivorEngine.submitAnswer(s, subjectId: other.id)
            XCTAssertEqual(s.usedIds.count, 2)
        }
    }

    // MARK: - Skip

    func testSkipCostsALifeAndAdvances() throws {
        let d = def([ringPrompt(), bigPrompt()], lives: 2)
        var s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: 1)
        let firstPromptId = s.currentPrompt?.id
        s = try SurvivorEngine.skip(s)
        XCTAssertEqual(s.livesRemaining, 1)
        XCTAssertNotEqual(s.currentPrompt?.id, firstPromptId)
    }

    // MARK: - Thin-pool tolerance

    func testSkipsUnanswerableLeadingPrompt() throws {
        // A prompt no entity satisfies (MVP) followed by a ring prompt; the pool has
        // no MVPs → initialize must open on an ANSWERABLE prompt.
        let mvp = SurvivorPrompt(id: "mvp", ask: "Name an MVP",
                                 predicate: .field(FieldConstraint(field: .careerMvp,
                                                                  op: .greaterOrEqual,
                                                                  value: .number(1))))
        let d = SurvivorDefinition(id: "t", title: "T", poolSource: .historical(.allEligible),
                                   config: SurvivorConfig(prompts: [mvp, ringPrompt()], lives: 2))
        // Force a seed where mvp would be first; the engine skips it regardless.
        for seed in UInt64(0)..<20 {
            let s = try SurvivorEngine.initialize(definition: d, pool: pool(), seed: seed)
            if s.status == .playing {
                XCTAssertNotEqual(s.currentPrompt?.id, "mvp",
                                  "should never open on the unanswerable MVP prompt (seed \(seed))")
            }
        }
    }
}
