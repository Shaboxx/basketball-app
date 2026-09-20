import XCTest
@testable import BasketballOffline

final class GameFeasibilityTests: XCTestCase {

    private func def(roster: RosterConfig, constraints: [RosterConstraint] = [],
                     selection: SelectionConfig = .snake) -> GameDefinition {
        GameDefinition(id: "t", title: "T", engineType: .rosterConstruction,
                       entityConstraints: [], rosterConstraints: constraints,
                       roster: roster, selection: selection, scoring: .none)
    }

    func testFillableStartingFive() {
        XCTAssertTrue(GameFeasibility.canComplete(
            definition: def(roster: .startingFive), participantCount: 2,
            pool: GameTestFixtures.tenManPool()))
    }

    func testPoolTooSmallForTwoRosters() {
        // 10-man pool, 2 seats × 5 slots fits exactly; 3 seats needs 15 → infeasible.
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .startingFive), participantCount: 3,
            pool: GameTestFixtures.tenManPool()))
    }

    func testMissingPositionIsInfeasible() {
        let noCenters = GameTestFixtures.tenManPool().filter { $0.position != "C" }
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .startingFive), participantCount: 1, pool: noCenters))
    }

    func testUniqueByTeamCanBeInfeasible() {
        // 5 slots, one player per team, but the pool spans only 2 teams.
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .positionless(5), constraints: [.uniqueBy(.team)]),
            participantCount: 1, pool: GameTestFixtures.tenManPool()))
        // 2 slots across 2 teams feasible.
        XCTAssertTrue(GameFeasibility.canComplete(
            definition: def(roster: .positionless(2), constraints: [.uniqueBy(.team)]),
            participantCount: 1, pool: GameTestFixtures.tenManPool()))
    }

    func testBacktrackingFindsNonGreedySolution() {
        // Flexible slot must NOT greedily take the only center.
        // Pool: one C, one PF. Slots: Big (PF|C) + strict C. Greedy putting the C
        // in "Big" first would strand strict C — backtracking must succeed.
        let pool = [GameTestFixtures.ent("c1", pos: "C"),
                    GameTestFixtures.ent("pf1", pos: "PF")]
        let roster = RosterConfig(slots: [
            RosterSlot(id: "BIG", label: "Big", allowedPositions: ["PF", "C"]),
            RosterSlot(id: "C", label: "C", allowedPositions: ["C"]),
        ])
        XCTAssertTrue(GameFeasibility.canComplete(
            definition: def(roster: roster), participantCount: 1, pool: pool))
    }

    func testMinCountWhereCheckedAtCompletion() {
        // Positionless pair, must include ≥1 center, pool has exactly one.
        let big = GameConstraint.field(FieldConstraint(field: .position, op: .equal,
                                                       value: .string("C")))
        let pool = [GameTestFixtures.ent("c1", pos: "C"),
                    GameTestFixtures.ent("g1", pos: "PG"),
                    GameTestFixtures.ent("g2", pos: "SG")]
        XCTAssertTrue(GameFeasibility.canComplete(
            definition: def(roster: .positionless(2), constraints: [.minCountWhere(big, 1)]),
            participantCount: 1, pool: pool))
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .positionless(2), constraints: [.minCountWhere(big, 3)]),
            participantCount: 1, pool: pool))
    }

    func testExhaustiveInfeasibilityTerminates() {
        // 3 unique-team slots over a 2-team pool: proving infeasibility requires
        // exhausting the tree — must return false, and fast.
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .positionless(3), constraints: [.uniqueBy(.team)]),
            participantCount: 1, pool: GameTestFixtures.tenManPool()))
    }

    func testInfeasibleMinCountPrunesOnLargePool() {
        // 200-player pool with only 2 centers, roster requires >= 3 centers.
        // minCountWhere never gates picks, so without the lookahead prune this
        // would exhaust ~P(200,5) leaves; with it, rejection is immediate.
        let pool = (0..<200).map { i in
            GameTestFixtures.ent("p\(i)", pos: i < 2 ? "C" : "PG", team: "T\(i % 30)")
        }
        let center = GameConstraint.field(FieldConstraint(field: .position, op: .equal,
                                                          value: .string("C")))
        let start = Date()
        XCTAssertFalse(GameFeasibility.canComplete(
            definition: def(roster: .positionless(5), constraints: [.minCountWhere(center, 3)]),
            participantCount: 1, pool: pool))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testNonSharedPoolOnlyNeedsOneRostersWorth() {
        // freePick (sharedPool=false): 3 participants can all build from the same 5.
        let five = Array(GameTestFixtures.tenManPool().prefix(5))
        XCTAssertTrue(GameFeasibility.canComplete(
            definition: def(roster: .positionless(5), selection: .freePick),
            participantCount: 3, pool: five))
    }

    func testInitializeRejectsDuplicateSlotIds() {
        // Two slots share an id → GameFeasibility.fill would collapse them to one
        // (false-feasible). initialize must reject the definition. (Sol review.)
        let dupRoster = RosterConfig(slots: [
            RosterSlot(id: "S", label: "S", allowedPositions: []),
            RosterSlot(id: "S", label: "S2", allowedPositions: []),
        ])
        let def = GameDefinition(
            id: "t", title: "T", engineType: .rosterConstruction,
            entityConstraints: [], rosterConstraints: [],
            roster: dupRoster, selection: .freePick, scoring: .none)
        XCTAssertThrowsError(try RosterConstructionEngine.initialize(
            definition: def,
            participants: [GameParticipant(id: 0, kind: .human, displayName: "You")],
            pool: GameTestFixtures.tenManPool(), seed: 1)) {
            XCTAssertEqual($0 as? GameEngineError, .infeasibleDefinition)
        }
    }
}
