import XCTest
@testable import BasketballOffline

final class GameResultTests: XCTestCase {

    private func finishedState(scoring: ScoringMethod,
                               seats: [[Double]]) -> RosterGameState {
        // Build a synthetic complete state: seats[i] = ratings on seat i's roster.
        let participants = seats.indices.map {
            GameParticipant(id: $0, kind: .human, displayName: "P\($0 + 1)")
        }
        var idCounter = 0
        let rosters: [[RosterAssignment]] = seats.map { ratings in
            ratings.enumerated().map { i, r in
                idCounter += 1
                return RosterAssignment(
                    slotId: "P\(i + 1)",
                    entity: GameTestFixtures.ent("e\(idCounter)", rating: r))
            }
        }
        let def = RosterConstructionEngineTests.definition(
            roster: .positionless(seats[0].count), scoring: scoring)
        return RosterGameState(
            definition: def, participants: participants,
            pool: rosters.flatMap { $0.map(\.entity) },
            rosters: rosters, pickedIds: [],
            turnSequence: [], turnIndex: 0, offerings: nil,
            rng: SeededRNG(seed: 1), status: .complete)
    }

    func testTeamRatingSumsAndPicksWinner() {
        let result = RosterConstructionEngine.buildResult(
            finishedState(scoring: .teamRating, seats: [[5, 5], [4, 7]]))
        XCTAssertEqual(result.scores, [10, 11])
        XCTAssertEqual(result.winnerSeat, 1)
    }

    func testExactTieHasNoWinner() {
        let result = RosterConstructionEngine.buildResult(
            finishedState(scoring: .teamRating, seats: [[6, 4], [3, 7]]))
        XCTAssertEqual(result.scores, [10, 10])
        XCTAssertNil(result.winnerSeat)
    }

    func testSoloGetsScoreButNoWinner() {
        let result = RosterConstructionEngine.buildResult(
            finishedState(scoring: .teamRating, seats: [[6, 4]]))
        XCTAssertEqual(result.scores, [10])
        XCTAssertNil(result.winnerSeat)
    }

    func testScoringNoneHasNoScoresOrWinner() {
        let result = RosterConstructionEngine.buildResult(
            finishedState(scoring: .none, seats: [[5], [9]]))
        XCTAssertNil(result.scores)
        XCTAssertNil(result.winnerSeat)
    }
}
