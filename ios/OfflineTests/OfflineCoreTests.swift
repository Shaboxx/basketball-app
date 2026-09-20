import XCTest
@testable import BasketballOffline

final class OfflineCoreTests: XCTestCase {
    func testSyntheticPoolUsesOriginalPlayerContract() {
        XCTAssertEqual(OfflineFixtures.players.count, 20)
        XCTAssertEqual(Set(OfflineFixtures.pool.map(\.id)).count, 20)
        XCTAssertEqual(Set(OfflineFixtures.pool.map(\.position)), ["PG", "SG", "SF", "PF", "C"])
    }

    func testSalaryMatchingPreservesCapAndApronDistinction() {
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .underCap, outgoing: 10_000_000, capRoom: 5_000_000), 15_250_000)
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overCap, outgoing: 10_000_000, capRoom: 0), 17_936_000)
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overSecondApron, outgoing: 10_000_000, capRoom: 0), 10_000_000)
        XCTAssertFalse(TradeCompliance.canMatchWithoutAggregation(incoming: [15_000_000], outgoing: [8_000_000, 8_000_000]))
    }

    func testQuizReproducibilityAndCompletion() throws {
        let a = try QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: OfflineFixtures.pool, seed: 42)
        let b = try QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: OfflineFixtures.pool, seed: 42)
        XCTAssertEqual(a, b)
        var state = a
        while let question = state.currentQuestion, state.status == .answering {
            state = try QuizEngine.answer(state, choiceIndex: question.correctIndex)
        }
        XCTAssertEqual(state.status, .complete)
        XCTAssertEqual(state.score, a.questions.count)
        XCTAssertThrowsError(try QuizEngine.answer(state, choiceIndex: 0))
    }

    func testQuizRejectsInvalidChoiceWithoutAdvancing() throws {
        let state = try QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: OfflineFixtures.pool, seed: 42)
        XCTAssertThrowsError(try QuizEngine.answer(state, choiceIndex: -1))
        XCTAssertEqual(state.currentIndex, 0)
    }

    func testCompositeDraftCompletesWithUniqueTeams() throws {
        var state = try RosterConstructionEngine.initialize(definition: GamePresets.createAPlayer,
            participants: [GameParticipant(id: 0, kind: .human, displayName: "Reviewer")],
            pool: OfflineFixtures.pool, seed: 42)
        var rng = SeededRNG(seed: 42)
        while state.status == .active {
            let pick = try XCTUnwrap(GameCPUPolicy.choosePick(state, seat: 0, rng: &rng))
            state = try RosterConstructionEngine.submitPick(state, seat: 0, entityId: pick.entityId, slotId: pick.slotId)
        }
        XCTAssertEqual(state.rosters[0].count, 4)
        XCTAssertEqual(Set(state.rosters[0].map { $0.entity.team }).count, 4)
        XCTAssertEqual(Set(state.rosters[0].map(\.slotId)).count, 4)
    }

    func testCompareIgnoresDuplicateEntitiesAndRejectsForeignChoice() throws {
        let state = try CompareEngine.initialize(definition: ComparePresets.biggerContract,
            pool: OfflineFixtures.pool + OfflineFixtures.pool, seed: 42)
        XCTAssertEqual(state.pool.count, 20)
        XCTAssertThrowsError(try CompareEngine.guess(state, subjectId: "not-in-pair"))
        let correct = state.pair.max { (state.entity($0)!.salary ?? 0) < (state.entity($1)!.salary ?? 0) }!
        XCTAssertEqual(try CompareEngine.guess(state, subjectId: correct).score, 1)
    }

    func testOfflineReportIsDeterministicAndInspectable() throws {
        let first = try OfflineReport.json()
        XCTAssertEqual(first, try OfflineReport.json())
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
        XCTAssertEqual(result["draft_complete"] as? Bool, true)
        XCTAssertEqual(result["quiz_questions"] as? Int, 8)
    }
}
