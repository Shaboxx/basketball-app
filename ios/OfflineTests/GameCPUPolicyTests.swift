import XCTest
@testable import BasketballOffline

final class GameCPUPolicyTests: XCTestCase {

    private func game(roster: RosterConfig = .positionless(2)) throws -> RosterGameState {
        try RosterConstructionEngine.initialize(
            definition: RosterConstructionEngineTests.definition(roster: roster),
            participants: RosterConstructionEngineTests.twoHumans(),
            pool: GameTestFixtures.tenManPool(), seed: 1)
    }

    func testChoosesFromTopCandidateWindowOnly() throws {
        let state = try game()
        // Ratings are 1...10; window is the top 4 → rating ≥ 7.
        for seed: UInt64 in 0..<20 {
            var rng = SeededRNG(seed: seed)
            let pick = GameCPUPolicy.choosePick(state, seat: 0, rng: &rng)!
            let entity = state.pool.first { $0.id == pick.entityId }!
            XCTAssertGreaterThanOrEqual(entity.rating, 7)
        }
    }

    func testPickIsAlwaysSubmittable() throws {
        var state = try game()
        var rng = SeededRNG(seed: 3)
        while state.status == .active {
            let seat = RosterConstructionEngine.currentSeat(state)!
            let pick = GameCPUPolicy.choosePick(state, seat: seat, rng: &rng)!
            XCTAssertNoThrow(state = try RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: pick.entityId, slotId: pick.slotId))
        }
        XCTAssertEqual(state.status, .complete)
    }

    func testDeterministicUnderSeed() throws {
        let state = try game()
        var a = SeededRNG(seed: 5); var b = SeededRNG(seed: 5)
        let pa = GameCPUPolicy.choosePick(state, seat: 0, rng: &a)!
        let pb = GameCPUPolicy.choosePick(state, seat: 0, rng: &b)!
        XCTAssertEqual(pa.entityId, pb.entityId)
        XCTAssertEqual(pa.slotId, pb.slotId)
    }

    func testFillsMostConstrainedSlotFirst() throws {
        // Big (PF|C) is tighter than a positionless bench slot — whichever big
        // the CPU takes must land in Big, keeping the flexible slot open. Both
        // pool players are bigs so the (weighted-random) entity choice can't
        // change the slot under test.
        let roster = RosterConfig(slots: [
            RosterSlot(id: "BIG", label: "Big", allowedPositions: ["PF", "C"]),
            RosterSlot(id: "ANY", label: "Any", allowedPositions: []),
        ])
        let state = try RosterConstructionEngine.initialize(
            definition: RosterConstructionEngineTests.definition(roster: roster),
            participants: [GameParticipant(id: 0, kind: .cpu, displayName: "CPU 1")],
            pool: [GameTestFixtures.ent("c1", pos: "C", rating: 10),
                   GameTestFixtures.ent("pf1", pos: "PF", rating: 9)], seed: 1)
        var rng = SeededRNG(seed: 1)
        let pick = GameCPUPolicy.choosePick(state, seat: 0, rng: &rng)!
        XCTAssertTrue(["c1", "pf1"].contains(pick.entityId))
        XCTAssertEqual(pick.slotId, "BIG")
    }

    func testBudgetReserveLetsCPUCompleteFullRosterUnderTightCap() throws {
        // Economy game where greedy-by-rating would strand the CPU: highest-rated
        // players are the priciest. A budget-blind CPU buys stars and can't fill
        // the rest; the reserve must keep enough to finish all slots.
        let def = GameDefinition(
            id: "t", title: "T", engineType: .rosterConstruction,
            entityConstraints: [], rosterConstraints: [],
            roster: .positionless(3), selection: .freePick, scoring: .teamRating,
            economy: EconomyConfig(pricingMethod: .databaseValue, startingBudget: 30_000_000))
        // ratings ascend with salary: cheap scrubs (rating low) + pricey stars.
        let pool = (0..<9).map { i in
            GameTestFixtures.ent("p\(i)", pos: ["PG","SG","SF"][i % 3],
                                 rating: Double(i), salary: (i + 1) * 5_000_000)
        }
        var state = try RosterConstructionEngine.initialize(
            definition: def,
            participants: [GameParticipant(id: 0, kind: .cpu, displayName: "CPU 1")],
            pool: pool, seed: 3)
        var rng = SeededRNG(seed: 3)
        while state.status == .active {
            let seat = RosterConstructionEngine.currentSeat(state)!
            guard let pick = GameCPUPolicy.choosePick(state, seat: seat, rng: &rng) else { break }
            state = try RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: pick.entityId, slotId: pick.slotId)
        }
        // The reserve must let the CPU fill all 3 slots (greedy would strand at 1-2).
        XCTAssertEqual(state.rosters[0].count, 3)
    }

    func testBudgetReserveCompletesFlexFiveWhenGreedyWouldStrand() throws {
        // flexFive (positional). B1 (PF/C) can ONLY be filled by pf1 (the sole
        // PF/C). A position-blind, rating-greedy CPU would spend pf1 on W2 (it
        // outrates sf1) and then can't fill B1 → stranded at 4/5. The position-
        // aware reserve must save pf1 for B1.
        let def = GameDefinition(
            id: "t", title: "T", engineType: .rosterConstruction,
            entityConstraints: [], rosterConstraints: [],
            roster: .flexFive, selection: .freePick, scoring: .teamRating,
            economy: EconomyConfig(pricingMethod: .databaseValue, startingBudget: 12_000_000))
        let pool = [
            GameTestFixtures.ent("pg1", pos: "PG", rating: 9, salary: 3_000_000),
            GameTestFixtures.ent("pg2", pos: "PG", rating: 8, salary: 3_000_000),
            GameTestFixtures.ent("sg1", pos: "SG", rating: 7, salary: 3_000_000),
            GameTestFixtures.ent("pf1", pos: "PF", rating: 6, salary: 2_000_000),
            GameTestFixtures.ent("sf1", pos: "SF", rating: 4, salary: 1_000_000),
        ]
        var state = try RosterConstructionEngine.initialize(
            definition: def,
            participants: [GameParticipant(id: 0, kind: .cpu, displayName: "CPU 1")],
            pool: pool, seed: 5)
        var rng = SeededRNG(seed: 5)
        while state.status == .active {
            let seat = RosterConstructionEngine.currentSeat(state)!
            guard let pick = GameCPUPolicy.choosePick(state, seat: seat, rng: &rng) else { break }
            state = try RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: pick.entityId, slotId: pick.slotId)
        }
        XCTAssertEqual(state.rosters[0].count, 5)   // all five flex slots filled
    }

    func testBudgetReserveRespectsUniqueByTeamAcrossDraftedPlayers() throws {
        // Budget + one-player-per-team. The reserve must count the seat's ALREADY
        // -drafted teams (via seededRoster), else it could reserve a candidate
        // whose only cheap completion reuses a team already on the roster →
        // strand. Assert the CPU fills all 3 slots with 3 DISTINCT teams.
        let def = GameDefinition(
            id: "t", title: "T", engineType: .rosterConstruction,
            entityConstraints: [], rosterConstraints: [.uniqueBy(.team)],
            roster: .positionless(3), selection: .freePick, scoring: .teamRating,
            economy: EconomyConfig(pricingMethod: .databaseValue, startingBudget: 12_000_000))
        // Two players per team A/B/C. Cheap on A/B, pricier stars everywhere.
        let pool = [
            GameTestFixtures.ent("a_cheap", team: "A", rating: 3, salary: 2_000_000),
            GameTestFixtures.ent("a_star",  team: "A", rating: 9, salary: 8_000_000),
            GameTestFixtures.ent("b_cheap", team: "B", rating: 3, salary: 2_000_000),
            GameTestFixtures.ent("b_star",  team: "B", rating: 8, salary: 8_000_000),
            GameTestFixtures.ent("c_cheap", team: "C", rating: 3, salary: 2_000_000),
            GameTestFixtures.ent("c_star",  team: "C", rating: 7, salary: 8_000_000),
        ]
        var state = try RosterConstructionEngine.initialize(
            definition: def,
            participants: [GameParticipant(id: 0, kind: .cpu, displayName: "CPU 1")],
            pool: pool, seed: 4)
        var rng = SeededRNG(seed: 4)
        while state.status == .active {
            let seat = RosterConstructionEngine.currentSeat(state)!
            guard let pick = GameCPUPolicy.choosePick(state, seat: seat, rng: &rng) else { break }
            state = try RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: pick.entityId, slotId: pick.slotId)
        }
        XCTAssertEqual(state.rosters[0].count, 3)
        let teams = state.rosters[0].map(\.entity.team)
        XCTAssertEqual(Set(teams).count, 3)   // three distinct teams — uniqueBy held
    }

    func testNilWhenNothingEligible() {
        // Hand-build a state whose pool is exhausted for the seat.
        let def = RosterConstructionEngineTests.definition(roster: .positionless(1))
        let e = GameTestFixtures.ent("only")
        let state = RosterGameState(
            definition: def,
            participants: RosterConstructionEngineTests.twoHumans(),
            pool: [e], rosters: [[], []],
            pickedIds: [e.id],       // shared pool already drained
            turnSequence: [0, 1], turnIndex: 1, offerings: nil,
            rng: SeededRNG(seed: 1), status: .active)
        var rng = SeededRNG(seed: 1)
        XCTAssertNil(GameCPUPolicy.choosePick(state, seat: 1, rng: &rng))
    }
}
