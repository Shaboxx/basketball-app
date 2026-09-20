import XCTest
@testable import BasketballOffline

/// Phase-6 T3: eligibility-rarity scoring — `100 / count` clamped 1...100.
final class GridRarityScorerTests: XCTestCase {

    private func player(id: String, franchises: Set<String> = [],
                        decades: Set<Int> = []) -> HistoricalPlayerEntity {
        HistoricalPlayerEntity(id: id, name: "P\(id)", appSlug: nil,
                               franchises: franchises, decades: decades, families: [],
                               careerRings: 0, careerMvp: 0, careerAllNba: 0,
                               careerAllStar: 0, careerAllDefense: 0, bestRating: 70)
    }

    func testRarityClamping() {
        XCTAssertEqual(GridRarityScorer.rarity(count: 1), 100)   // 100/1
        XCTAssertEqual(GridRarityScorer.rarity(count: 2), 50)    // 100/2
        XCTAssertEqual(GridRarityScorer.rarity(count: 4), 25)
        XCTAssertEqual(GridRarityScorer.rarity(count: 100), 1)   // 100/100 = 1
        XCTAssertEqual(GridRarityScorer.rarity(count: 1000), 1)  // clamped floor 1
        XCTAssertEqual(GridRarityScorer.rarity(count: 0), 100)   // count=0 guarded → treat as 1
    }

    func testScalingApplies() {
        // scaling 2 doubles the base then clamps.
        XCTAssertEqual(GridRarityScorer.rarity(count: 4, scaling: 2.0), 50)  // 25*2
        XCTAssertEqual(GridRarityScorer.rarity(count: 1, scaling: 2.0), 100) // clamp ceiling
    }

    func testEligibleCountOverPool() {
        let pool = [
            player(id: "1", franchises: ["LAL"], decades: [2000]),
            player(id: "2", franchises: ["LAL"], decades: [2010]),
            player(id: "3", franchises: ["LAL"], decades: [2000]),
            player(id: "4", franchises: ["BOS"], decades: [2000]),
        ]
        // LAL × 2000s → players 1 & 3 (2).
        let count = GridRarityScorer.eligibleCount(row: .franchise("LAL"),
                                                   col: .decade(2000), pool: pool)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(GridRarityScorer.rarity(count: count), 50)
        // A no-answer cell → count 0.
        XCTAssertEqual(GridRarityScorer.eligibleCount(row: .franchise("MIA"),
                                                     col: .decade(2000), pool: pool), 0)
    }
}
