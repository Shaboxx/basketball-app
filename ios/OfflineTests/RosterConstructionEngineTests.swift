import XCTest
@testable import BasketballOffline

final class RosterConstructionEngineTests: XCTestCase {

    // Shared helpers for this class and later engine tasks.
    static func definition(roster: RosterConfig = .positionless(2),
                           entity: [GameConstraint] = [],
                           rosterCs: [RosterConstraint] = [],
                           selection: SelectionConfig = .snake,
                           scoring: ScoringMethod = .none) -> GameDefinition {
        GameDefinition(id: "t", title: "T", engineType: .rosterConstruction,
                       entityConstraints: entity, rosterConstraints: rosterCs,
                       roster: roster, selection: selection, scoring: scoring)
    }

    static func twoHumans() -> [GameParticipant] {
        [GameParticipant(id: 0, kind: .human, displayName: "Player 1"),
         GameParticipant(id: 1, kind: .human, displayName: "Player 2")]
    }

    func testInitializeFiltersPoolByEntityConstraints() throws {
        let starOnly: [GameConstraint] = [.field(FieldConstraint(
            field: .rating, op: .greaterOrEqual, value: .number(5)))]
        let state = try RosterConstructionEngine.initialize(
            definition: Self.definition(entity: starOnly),
            participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
        XCTAssertEqual(state.pool.count, 6)   // ratings 5...10
        XCTAssertTrue(state.pool.allSatisfy { $0.rating >= 5 })
    }

    func testInitializeThrowsWhenInfeasible() {
        // 2 seats × 2 positionless slots needs 4; give 3.
        XCTAssertThrowsError(try RosterConstructionEngine.initialize(
            definition: Self.definition(),
            participants: Self.twoHumans(),
            pool: Array(GameTestFixtures.tenManPool().prefix(3)), seed: 1)) { error in
            XCTAssertEqual(error as? GameEngineError, .infeasibleDefinition)
        }
    }

    func testSnakeTurnSequence() {
        XCTAssertEqual(
            RosterConstructionEngine.turnSequence(seats: 3, rounds: 3, method: .snake),
            [0, 1, 2, 2, 1, 0, 0, 1, 2])
    }

    func testFreePickTurnSequenceIsRoundRobin() {
        XCTAssertEqual(
            RosterConstructionEngine.turnSequence(seats: 2, rounds: 2, method: .freePick),
            [0, 1, 0, 1])
    }

    func testSoloTurnSequence() {
        XCTAssertEqual(
            RosterConstructionEngine.turnSequence(seats: 1, rounds: 3, method: .snake),
            [0, 0, 0])
    }

    func testInitialStateIsActiveAtTurnZero() throws {
        let state = try RosterConstructionEngine.initialize(
            definition: Self.definition(), participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.turnIndex, 0)
        XCTAssertEqual(RosterConstructionEngine.currentSeat(state), 0)
        XCTAssertEqual(state.rosters, [[], []])
        XCTAssertNil(state.offerings)
    }

    // MARK: pick flow

    private func startedGame(
        roster: RosterConfig = .positionless(2),
        rosterCs: [RosterConstraint] = [],
        selection: SelectionConfig = .snake
    ) throws -> RosterGameState {
        try RosterConstructionEngine.initialize(
            definition: Self.definition(roster: roster, rosterCs: rosterCs,
                                        selection: selection),
            participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
    }

    func testValidSlotsRespectPositionsAndFill() throws {
        let state = try RosterConstructionEngine.initialize(
            definition: Self.definition(roster: .flexFive),
            participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
        let pg = state.pool.first { $0.position == "PG" }!
        let slots = RosterConstructionEngine.validSlots(state, seat: 0, entity: pg)
        XCTAssertEqual(Set(slots.map(\.id)), ["G1", "G2"])
    }

    func testSubmitPickHappyPathAdvancesTurn() throws {
        var state = try startedGame()
        let pick = state.pool[0]
        state = try RosterConstructionEngine.submitPick(state, seat: 0,
                                                        entityId: pick.id, slotId: "P1")
        XCTAssertEqual(state.rosters[0], [RosterAssignment(slotId: "P1", entity: pick)])
        XCTAssertTrue(state.pickedIds.contains(pick.id))
        XCTAssertEqual(state.turnIndex, 1)
        XCTAssertEqual(RosterConstructionEngine.currentSeat(state), 1)
    }

    func testSubmitPickWrongSeatThrows() throws {
        let state = try startedGame()
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 1, entityId: state.pool[0].id, slotId: "P1")) {
            XCTAssertEqual($0 as? GameEngineError, .notYourTurn)
        }
    }

    func testSharedPoolPickIsUnavailableToOthers() throws {
        var state = try startedGame()
        let pick = state.pool[0]
        state = try RosterConstructionEngine.submitPick(state, seat: 0,
                                                        entityId: pick.id, slotId: "P1")
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 1, entityId: pick.id, slotId: "P1")) {
            XCTAssertEqual($0 as? GameEngineError, .entityUnavailable)
        }
        XCTAssertFalse(RosterConstructionEngine.eligibleEntities(state, seat: 1)
            .contains(pick))
    }

    func testNonSharedPoolAllowsCrossRosterDuplicates() throws {
        var state = try RosterConstructionEngine.initialize(
            definition: Self.definition(selection: .freePick),
            participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
        let pick = state.pool[0]
        state = try RosterConstructionEngine.submitPick(state, seat: 0,
                                                        entityId: pick.id, slotId: "P1")
        // Seat 1 may take the same player (own-roster duplicates still blocked).
        state = try RosterConstructionEngine.submitPick(state, seat: 1,
                                                        entityId: pick.id, slotId: "P1")
        XCTAssertEqual(state.rosters[1][0].entity, pick)
    }

    func testFilledSlotThrows() throws {
        var state = try startedGame()
        state = try RosterConstructionEngine.submitPick(
            state, seat: 0, entityId: state.pool[0].id, slotId: "P1")
        state = try RosterConstructionEngine.submitPick(
            state, seat: 1, entityId: state.pool[1].id, slotId: "P1")
        // Snake: seat 1 again. Its P1 is filled.
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 1, entityId: state.pool[2].id, slotId: "P1")) {
            XCTAssertEqual($0 as? GameEngineError, .slotFilled)
        }
    }

    func testSlotRejectsWrongPosition() throws {
        let state = try RosterConstructionEngine.initialize(
            definition: Self.definition(roster: .startingFive),
            participants: Self.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
        let center = state.pool.first { $0.position == "C" }!
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 0, entityId: center.id, slotId: "PG")) {
            XCTAssertEqual($0 as? GameEngineError, .slotRejectsEntity)
        }
    }

    func testRosterConstraintViolationThrowsAndFiltersEligibility() throws {
        var state = try startedGame(rosterCs: [.uniqueBy(.team)])
        let aaa = state.pool.first { $0.team == "AAA" }!
        state = try RosterConstructionEngine.submitPick(state, seat: 0,
                                                        entityId: aaa.id, slotId: "P1")
        state = try RosterConstructionEngine.submitPick(
            state, seat: 1, entityId: state.pool.first { $0.team == "BBB" }!.id,
            slotId: "P1")
        // Snake round 2: seat 1 then seat 0. Give seat 1 an AAA player (legal for it).
        let aaa2 = RosterConstructionEngine.eligibleEntities(state, seat: 1)
            .first { $0.team == "AAA" }!
        state = try RosterConstructionEngine.submitPick(state, seat: 1,
                                                        entityId: aaa2.id, slotId: "P2")
        // Seat 0 already has an AAA player → all remaining AAA are ineligible for it.
        XCTAssertTrue(RosterConstructionEngine.eligibleEntities(state, seat: 0)
            .allSatisfy { $0.team == "BBB" })
        let aaa3 = state.pool.first {
            $0.team == "AAA" && !state.pickedIds.contains($0.id)
        }!
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 0, entityId: aaa3.id, slotId: "P2")) {
            XCTAssertEqual($0 as? GameEngineError, .rosterConstraintViolated)
        }
    }

    func testGameCompletesWhenAllRostersFull() throws {
        var state = try startedGame()   // 2 seats × 2 slots = 4 picks
        for _ in 0..<4 {
            let seat = RosterConstructionEngine.currentSeat(state)!
            let e = RosterConstructionEngine.eligibleEntities(state, seat: seat).first!
            let slot = RosterConstructionEngine.validSlots(state, seat: seat, entity: e).first!
            state = try RosterConstructionEngine.submitPick(state, seat: seat,
                                                            entityId: e.id, slotId: slot.id)
        }
        XCTAssertEqual(state.status, .complete)
        XCTAssertNil(RosterConstructionEngine.currentSeat(state))
        XCTAssertTrue(state.rosters.allSatisfy { $0.count == 2 })
    }
}
