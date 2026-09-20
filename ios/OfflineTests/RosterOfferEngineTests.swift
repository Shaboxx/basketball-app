import XCTest
@testable import BasketballOffline

final class RosterOfferEngineTests: XCTestCase {

    private func offerGame(seed: UInt64 = 1, perTurn: Int = 3) throws -> RosterGameState {
        try RosterConstructionEngine.initialize(
            definition: RosterConstructionEngineTests.definition(
                roster: .positionless(2), selection: .randomOffer(perTurn)),
            participants: RosterConstructionEngineTests.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: seed)
    }

    func testInitializeRollsFirstOfferings() throws {
        let state = try offerGame()
        XCTAssertEqual(state.offerings?.count, 3)
    }

    func testOfferingsAreLegalPicks() throws {
        let state = try offerGame()
        let eligibleIds = Set(RosterConstructionEngine
            .eligibleEntities(state, seat: 0).map(\.id))
        XCTAssertEqual(eligibleIds, Set(state.offerings!))
    }

    func testPickOutsideOfferingsThrows() throws {
        let state = try offerGame()
        let outside = state.pool.first { !state.offerings!.contains($0.id) }!
        XCTAssertThrowsError(try RosterConstructionEngine.submitPick(
            state, seat: 0, entityId: outside.id, slotId: "P1")) {
            XCTAssertEqual($0 as? GameEngineError, .notAnOffering)
        }
    }

    func testPickRerollsOfferingsForNextTurn() throws {
        var state = try offerGame()
        let pick = state.offerings![0]
        state = try RosterConstructionEngine.submitPick(state, seat: 0,
                                                        entityId: pick, slotId: "P1")
        XCTAssertEqual(state.offerings?.count, 3)          // next seat's offer
        XCTAssertFalse(state.offerings!.contains(pick))    // picked player gone
    }

    func testSameSeedSameOfferings() throws {
        let a = try offerGame(seed: 99)
        let b = try offerGame(seed: 99)
        XCTAssertEqual(a.offerings, b.offerings)
        XCTAssertNotEqual(a.offerings, try offerGame(seed: 100).offerings)
    }

    func testOfferSmallerThanRequestWhenPoolThin() throws {
        // 4-man pool, 2×2 slots: last turn has exactly 1 candidate left.
        var state = try RosterConstructionEngine.initialize(
            definition: RosterConstructionEngineTests.definition(
                roster: .positionless(2), selection: .randomOffer(3)),
            participants: RosterConstructionEngineTests.twoHumans(),
            pool: Array(GameTestFixtures.tenManPool().prefix(4)), seed: 1)
        for _ in 0..<3 {
            let seat = RosterConstructionEngine.currentSeat(state)!
            let id = state.offerings!.first!
            state = try RosterConstructionEngine.submitPick(state, seat: seat,
                                                            entityId: id, slotId:
                RosterConstructionEngine.validSlots(
                    state, seat: seat,
                    entity: state.pool.first { $0.id == id }!).first!.id)
        }
        XCTAssertEqual(state.offerings?.count, 1)
    }
}
