import XCTest
@testable import BasketballOffline

final class BracketScorerTests: XCTestCase {

    private func pool(_ n: Int) -> [GameEntityRecord] {
        (0..<n).map {
            GameEntityRecord(id: "p\($0)", name: "P\($0)", team: "T\($0)",
                             position: "PG", salary: nil, rating: Double(n - $0))
        }
    }

    private func def(fieldSize: Int, scoring: BracketScoring) -> BracketDefinition {
        BracketDefinition(id: "b", title: "B", fieldSize: fieldSize,
                          seedByRating: true, scoring: scoring)
    }

    func testChampionIsLastPick() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4, scoring: .none), pool: pool(4), seed: 1)
        // seeds [p0,p3,p1,p2]. Pick p3, p2, p2.
        state = try BracketEngine.advance(state, winnerId: "p3")
        state = try BracketEngine.advance(state, winnerId: "p2")
        state = try BracketEngine.advance(state, winnerId: "p2")
        let r = BracketScorer.buildResult(state)
        XCTAssertEqual(r.champion?.id, "p2")
        XCTAssertNil(r.modelAgreementCount)   // scoring == .none
        XCTAssertEqual(r.totalMatchups, 3)
    }

    func testChampionNilBeforeComplete() throws {
        let state = try BracketEngine.initialize(
            definition: def(fieldSize: 4, scoring: .none), pool: pool(4), seed: 1)
        XCTAssertNil(BracketScorer.buildResult(state).champion)
    }

    func testModelAgreementPerfectWhenAlwaysPickingHigherSeed() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4, scoring: .modelAgreement), pool: pool(4), seed: 1)
        // Always pick the higher-rating (left) side.
        while let mu = BracketEngine.currentMatchup(state) {
            let higher = mu.0.rating >= mu.1.rating ? mu.0.id : mu.1.id
            state = try BracketEngine.advance(state, winnerId: higher)
        }
        let r = BracketScorer.buildResult(state)
        XCTAssertEqual(r.modelAgreementCount, 3)   // 3/3
        XCTAssertEqual(r.champion?.id, "p0")       // top seed wins
    }

    func testModelAgreementCountsUpsets() throws {
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4, scoring: .modelAgreement), pool: pool(4), seed: 1)
        // seeds [p0,p3,p1,p2]. Round0: pick the LOWER seed each time (2 disagreements).
        state = try BracketEngine.advance(state, winnerId: "p3")   // upset vs p0
        state = try BracketEngine.advance(state, winnerId: "p2")   // upset vs p1
        // Final: p3 vs p2 → p3 rated higher (rating 1 vs 0... p3=n-3, p2=n-2? recheck).
        // pool(4): p0=4,p1=3,p2=2,p3=1. So p3(1) vs p2(2): higher=p2. Pick p2 = agree.
        state = try BracketEngine.advance(state, winnerId: "p2")
        let r = BracketScorer.buildResult(state)
        XCTAssertEqual(r.modelAgreementCount, 1)   // only the final agreed
    }

    func testModelAgreementTieCountsAsAgreement() throws {
        // Two equal-rated entities in a matchup: any pick agrees.
        let equalPool = [
            GameEntityRecord(id: "a", name: "A", team: "T0", position: "PG", salary: nil, rating: 5),
            GameEntityRecord(id: "b", name: "B", team: "T1", position: "PG", salary: nil, rating: 5),
            GameEntityRecord(id: "c", name: "C", team: "T2", position: "PG", salary: nil, rating: 5),
            GameEntityRecord(id: "d", name: "D", team: "T3", position: "PG", salary: nil, rating: 5),
        ]
        var state = try BracketEngine.initialize(
            definition: def(fieldSize: 4, scoring: .modelAgreement), pool: equalPool, seed: 1)
        while let mu = BracketEngine.currentMatchup(state) {
            state = try BracketEngine.advance(state, winnerId: mu.1.id)   // always right
        }
        XCTAssertEqual(BracketScorer.buildResult(state).modelAgreementCount, 3)
    }
}
