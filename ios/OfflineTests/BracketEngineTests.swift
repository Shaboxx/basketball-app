import XCTest
@testable import BasketballOffline

final class BracketEngineTests: XCTestCase {

    // MARK: - Fixtures

    /// n distinct entities, teams T0…T(n-1), ratings n…1 desc so id order and
    /// rating order are known (p0 highest).
    private func pool(_ n: Int) -> [GameEntityRecord] {
        (0..<n).map {
            GameEntityRecord(id: "p\($0)", name: "P\($0)", team: "T\($0)",
                             position: "PG", salary: nil, rating: Double(n - $0))
        }
    }

    private func def(fieldSize: Int, seedByRating: Bool = true,
                     scoring: BracketScoring = .modelAgreement) -> BracketDefinition {
        BracketDefinition(id: "b", title: "B", fieldSize: fieldSize,
                          seedByRating: seedByRating, scoring: scoring)
    }

    // MARK: - Initialize

    func testInvalidFieldSizeThrows() {
        XCTAssertThrowsError(try BracketEngine.initialize(
            definition: def(fieldSize: 6), pool: pool(16), seed: 1)) { e in
            XCTAssertEqual(e as? BracketError, .invalidFieldSize)
        }
    }

    func testNotEnoughEntitiesThrows() {
        XCTAssertThrowsError(try BracketEngine.initialize(
            definition: def(fieldSize: 8), pool: pool(5), seed: 1)) { e in
            XCTAssertEqual(e as? BracketError, .notEnoughEntities)
        }
    }

    func testDedupByIdBeforeCounting() {
        // 4 unique + 4 duplicates → only 4 distinct → not enough for 8.
        let base = pool(4)
        let dupes = base + base
        XCTAssertThrowsError(try BracketEngine.initialize(
            definition: def(fieldSize: 8), pool: dupes, seed: 1)) { e in
            XCTAssertEqual(e as? BracketError, .notEnoughEntities)
        }
    }

    func testSeedOrderTopSeedsMeetLate() throws {
        let state = try BracketEngine.initialize(
            definition: def(fieldSize: 4), pool: pool(4), seed: 1)
        // field sorted best→worst: p0,p1,p2,p3. Seed order slots = [1,4,2,3].
        XCTAssertEqual(state.seeds.map(\.id), ["p0", "p3", "p1", "p2"])
    }

    func testSeedOrderEightSeeds() {
        let field = (0..<8).map {
            GameEntityRecord(id: "s\($0)", name: "S", team: "T\($0)", position: "PG",
                             salary: nil, rating: Double(8 - $0))
        }
        let ordered = BracketEngine.seedOrder(field)
        // Standard 8-bracket slot order: seeds 1,8,4,5,2,7,3,6 (0-based indices).
        XCTAssertEqual(ordered.map(\.id),
                       ["s0", "s7", "s3", "s4", "s1", "s6", "s2", "s5"])
    }

    func testRandomFieldIsSeededDeterministic() throws {
        let a = try BracketEngine.initialize(
            definition: def(fieldSize: 4, seedByRating: false, scoring: .none),
            pool: pool(10), seed: 42)
        let b = try BracketEngine.initialize(
            definition: def(fieldSize: 4, seedByRating: false, scoring: .none),
            pool: pool(10), seed: 42)
        XCTAssertEqual(a.seeds.map(\.id), b.seeds.map(\.id))
    }

    // MARK: - Progression

    func testFourFieldFullPlaythrough() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4), pool: pool(4), seed: 1)
        // seeds = [p0, p3, p1, p2]. Round0 matchups: (p0 vs p3)(p1 vs p2).
        XCTAssertEqual(BracketEngine.currentRound(state), 0)
        var mu = BracketEngine.currentMatchup(state)!
        XCTAssertEqual([mu.0.id, mu.1.id], ["p0", "p3"])
        state = try BracketEngine.advance(state, winnerId: "p0")   // pick p0
        mu = BracketEngine.currentMatchup(state)!
        XCTAssertEqual([mu.0.id, mu.1.id], ["p1", "p2"])
        state = try BracketEngine.advance(state, winnerId: "p1")   // pick p1
        // Final: winners p0 vs p1.
        XCTAssertEqual(BracketEngine.currentRound(state), 1)
        mu = BracketEngine.currentMatchup(state)!
        XCTAssertEqual([mu.0.id, mu.1.id], ["p0", "p1"])
        state = try BracketEngine.advance(state, winnerId: "p1")   // champion p1
        XCTAssertEqual(state.status, .complete)
        XCTAssertNil(BracketEngine.currentMatchup(state))
        XCTAssertNil(BracketEngine.currentMatchupIndex(state))
    }

    func testTotalMatchups() {
        XCTAssertEqual(BracketEngine.totalMatchups(fieldSize: 4), 3)
        XCTAssertEqual(BracketEngine.totalMatchups(fieldSize: 8), 7)
        XCTAssertEqual(BracketEngine.totalMatchups(fieldSize: 16), 15)
    }

    func testPickRangeLayout() {
        // 8-field: round0 [0,4), round1 [4,6), round2 [6,7).
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 0).start, 0)
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 0).count, 4)
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 1).start, 4)
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 1).count, 2)
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 2).start, 6)
        XCTAssertEqual(BracketEngine.pickRange(fieldSize: 8, round: 2).count, 1)
    }

    // MARK: - Typed errors

    func testAdvanceUnknownEntity() throws {
        let state = try BracketEngine.initialize(
            definition: def(fieldSize: 4), pool: pool(4), seed: 1)
        XCTAssertThrowsError(try BracketEngine.advance(state, winnerId: "nobody")) { e in
            XCTAssertEqual(e as? BracketError, .unknownEntity)
        }
    }

    func testAdvanceNotInMatchup() throws {
        let state = try BracketEngine.initialize(
            definition: def(fieldSize: 4), pool: pool(4), seed: 1)
        // Current matchup is p0 vs p3; p1 is a valid seed but not in this matchup.
        XCTAssertThrowsError(try BracketEngine.advance(state, winnerId: "p1")) { e in
            XCTAssertEqual(e as? BracketError, .notInMatchup)
        }
    }

    func testAdvanceOnCompleteThrows() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4), pool: pool(4), seed: 1)
        state = try BracketEngine.advance(state, winnerId: "p0")
        state = try BracketEngine.advance(state, winnerId: "p1")
        state = try BracketEngine.advance(state, winnerId: "p0")
        XCTAssertEqual(state.status, .complete)
        XCTAssertThrowsError(try BracketEngine.advance(state, winnerId: "p0")) { e in
            XCTAssertEqual(e as? BracketError, .complete)
        }
    }

    func testReplayFromFixedSeedIsExact() throws {
        func run() throws -> [String] {
            var state = try BracketEngine.initialize(
                definition: def(fieldSize: 8, seedByRating: false, scoring: .none),
                pool: pool(20), seed: 7)
            var picks: [String] = []
            while let mu = BracketEngine.currentMatchup(state) {
                state = try BracketEngine.advance(state, winnerId: mu.0.id)  // always left
                picks.append(mu.0.id)
            }
            return picks + [state.seeds.map(\.id).joined()]
        }
        XCTAssertEqual(try run(), try run())
    }

    func testStateRoundTripsCodable() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 8), pool: pool(8), seed: 3)
        state = try BracketEngine.advance(state, winnerId:
            BracketEngine.currentMatchup(state)!.0.id)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(BracketState.self, from: data)
        XCTAssertEqual(back, state)
    }
}
