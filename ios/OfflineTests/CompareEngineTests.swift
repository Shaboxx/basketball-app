import XCTest
@testable import BasketballOffline

final class CompareEngineTests: XCTestCase {

    private func pool() -> [GameEntityRecord] {
        (0..<10).map { GameTestFixtures.ent("p\($0)", rating: Double($0)) }
    }

    private func start(_ metric: CompareMetric = .overall,
                       _ dir: CompareDirection = .higher,
                       seed: UInt64 = 1) throws -> CompareState {
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: metric, direction: dir))
        return try CompareEngine.initialize(definition: def, pool: pool(), seed: seed)
    }

    func testInitializeFiltersToMetricAndOpensAPair() throws {
        let state = try start()
        XCTAssertEqual(state.pool.count, 10)
        XCTAssertEqual(state.pair.count, 2)
        XCTAssertNotEqual(state.pair[0], state.pair[1])
        // R1: the offered pair has differing values.
        XCTAssertNotEqual(CompareMetric.overall.value(state.entity(state.pair[0])!),
                          CompareMetric.overall.value(state.entity(state.pair[1])!))
        XCTAssertEqual(state.score, 0)
        XCTAssertEqual(state.status, .active)
    }

    func testInitializeThrowsWhenMetricAbsentEverywhere() {
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .minutes, direction: .higher))
        XCTAssertThrowsError(try CompareEngine.initialize(definition: def, pool: pool(), seed: 1)) {
            XCTAssertEqual($0 as? CompareError, .notEnoughComparable)
        }
    }

    // R1: all-equal metric values → no real answer → throws.
    func testInitializeThrowsWhenAllValuesEqual() {
        let flat = (0..<10).map {
            GameEntityRecord(id: "p\($0)", name: "P", team: "T", position: "PG",
                             salary: 5_000_000, rating: 1)
        }
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .salary, direction: .higher))
        XCTAssertThrowsError(try CompareEngine.initialize(definition: def, pool: flat, seed: 1)) {
            XCTAssertEqual($0 as? CompareError, .notEnoughComparable)
        }
    }

    // R3: duplicate ids don't corrupt the pool / pair lookup.
    func testDedupsPoolById() throws {
        let dup = pool() + [GameTestFixtures.ent("p9", rating: 9)]
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .overall, direction: .higher))
        let state = try CompareEngine.initialize(definition: def, pool: dup, seed: 1)
        XCTAssertEqual(Set(state.pool.map(\.id)).count, state.pool.count)
    }

    func testCorrectGuessIncrementsAndOpensValidPair() throws {
        var state = try start()
        let a = state.entity(state.pair[0])!, b = state.entity(state.pair[1])!
        let higher = a.rating > b.rating ? a.id : b.id
        let beforeRng = state.rng
        state = try CompareEngine.guess(state, subjectId: higher)
        XCTAssertEqual(state.score, 1)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.lastCorrect, true)
        XCTAssertNotEqual(state.rng, beforeRng)                 // rng advanced
        XCTAssertNotEqual(state.pair[0], state.pair[1])         // valid distinct pair
        XCTAssertNotEqual(CompareMetric.overall.value(state.entity(state.pair[0])!),
                          CompareMetric.overall.value(state.entity(state.pair[1])!))
    }

    func testWrongGuessEndsTheGame() throws {
        var state = try start()
        let a = state.entity(state.pair[0])!, b = state.entity(state.pair[1])!
        let lower = a.rating < b.rating ? a.id : b.id
        state = try CompareEngine.guess(state, subjectId: lower)
        XCTAssertEqual(state.score, 0)
        XCTAssertEqual(state.status, .complete)
        XCTAssertEqual(state.lastCorrect, false)
    }

    func testLowerDirectionInvertsCorrectness() throws {
        var state = try start(.overall, .lower)
        let a = state.entity(state.pair[0])!, b = state.entity(state.pair[1])!
        let lower = a.rating < b.rating ? a.id : b.id
        state = try CompareEngine.guess(state, subjectId: lower)
        XCTAssertEqual(state.lastCorrect, true)
        XCTAssertEqual(state.score, 1)
    }

    func testGuessOutsidePairThrows() throws {
        let state = try start()
        let outsider = pool().first { !state.pair.contains($0.id) }!
        XCTAssertThrowsError(try CompareEngine.guess(state, subjectId: outsider.id)) {
            XCTAssertEqual($0 as? CompareError, .notInPair)
        }
    }

    // R4: no guesses after the game is over.
    func testGuessAfterCompleteThrows() throws {
        var state = try start()
        let a = state.entity(state.pair[0])!, b = state.entity(state.pair[1])!
        let lower = a.rating < b.rating ? a.id : b.id
        state = try CompareEngine.guess(state, subjectId: lower)   // wrong → complete
        XCTAssertThrowsError(try CompareEngine.guess(state, subjectId: state.pair[0])) {
            XCTAssertEqual($0 as? CompareError, .gameComplete)
        }
    }

    func testSameSeedSameSequence() throws {
        let a = try start(seed: 7)
        let b = try start(seed: 7)
        XCTAssertEqual(a.pair, b.pair)
    }

    // R9: entities missing the metric are filtered out of the pool.
    func testInitializeFiltersOutNilMetric() throws {
        let withMin = [
            GameEntityRecord(id: "m1", name: "M1", team: "T", position: "PG",
                             salary: 1, rating: 1, minutes: 30),
            GameEntityRecord(id: "m2", name: "M2", team: "T", position: "PG",
                             salary: 1, rating: 1, minutes: 20),
        ]
        let without = (0..<3).map { GameTestFixtures.ent("n\($0)", rating: 1) }   // no minutes
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .minutes, direction: .higher))
        let state = try CompareEngine.initialize(definition: def, pool: withMin + without, seed: 1)
        XCTAssertEqual(Set(state.pool.map(\.id)), ["m1", "m2"])
    }

    // R9: the CONFIGURED metric drives correctness, not always rating.
    func testConfiguredMetricDrivesCorrectness() throws {
        // salary order is OPPOSITE to rating: hi has best rating but least salary.
        let hi = GameEntityRecord(id: "hi", name: "Hi", team: "T", position: "PG",
                                  salary: 1_000_000, rating: 9)
        let lo = GameEntityRecord(id: "lo", name: "Lo", team: "T", position: "PG",
                                  salary: 50_000_000, rating: 1)
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .salary, direction: .higher))
        var state = try CompareEngine.initialize(definition: def, pool: [hi, lo], seed: 1)
        state = try CompareEngine.guess(state, subjectId: "lo")   // lo wins on SALARY
        XCTAssertEqual(state.lastCorrect, true)
    }
}
