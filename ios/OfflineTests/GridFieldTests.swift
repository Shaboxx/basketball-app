import XCTest
@testable import BasketballOffline

/// Phase-6 T2: `GridAxis` SET-membership over a distinct player, self-contained and
/// NOT touching the scalar `GameField`/`GameConstraintEvaluator`.
final class GridFieldTests: XCTestCase {

    private func player(id: String = "1", franchises: Set<String> = [],
                        decades: Set<Int> = [], families: Set<String> = [],
                        rings: Int = 0, allNba: Int = 0, allStar: Int = 0) -> HistoricalPlayerEntity {
        HistoricalPlayerEntity(id: id, name: "P\(id)", appSlug: nil,
                               franchises: franchises, decades: decades, families: families,
                               careerRings: rings, careerMvp: 0, careerAllNba: allNba,
                               careerAllStar: allStar, careerAllDefense: 0, bestRating: 70)
    }

    func testFranchiseMembership() {
        let p = player(franchises: ["LAL", "BOS"])
        XCTAssertTrue(p.satisfies(.franchise("LAL")))
        XCTAssertTrue(p.satisfies(.franchise("BOS")))
        XCTAssertFalse(p.satisfies(.franchise("MIA")))
    }

    func testDecadeMembership() {
        let p = player(decades: [2000, 2010])
        XCTAssertTrue(p.satisfies(.decade(2000)))
        XCTAssertFalse(p.satisfies(.decade(1990)))
    }

    func testPositionFamilyMembership() {
        let p = player(families: ["GUARD"])
        XCTAssertTrue(p.satisfies(.positionFamily("GUARD")))
        XCTAssertFalse(p.satisfies(.positionFamily("BIG")))
    }

    func testAwardMembership() {
        let ringed = player(rings: 2, allNba: 0, allStar: 3)
        XCTAssertTrue(ringed.satisfies(.award("ring")))
        XCTAssertTrue(ringed.satisfies(.award("allStar")))
        XCTAssertFalse(ringed.satisfies(.award("allNba")))     // 0 → fails
        XCTAssertFalse(ringed.satisfies(.award("unknownKey"))) // unknown never satisfies
    }

    func testCellIsLogicalAnd() {
        // Belongs to LAL AND won a ring → satisfies; missing the award fails.
        let ringedLaker = player(franchises: ["LAL"], rings: 1)
        XCTAssertTrue(ringedLaker.satisfies(row: .franchise("LAL"), col: .award("ring")))
        let ringlessLaker = player(franchises: ["LAL"], rings: 0)
        XCTAssertFalse(ringlessLaker.satisfies(row: .franchise("LAL"), col: .award("ring")))
        // Right award, wrong franchise → fails.
        let ringedCeltic = player(franchises: ["BOS"], rings: 1)
        XCTAssertFalse(ringedCeltic.satisfies(row: .franchise("LAL"), col: .award("ring")))
    }

    func testDisplayLabels() {
        XCTAssertEqual(GridAxis.franchise("LAL").displayLabel, "LAL")
        XCTAssertEqual(GridAxis.decade(2010).displayLabel, "2010s")
        XCTAssertEqual(GridAxis.positionFamily("GUARD").displayLabel, "Guard")
        XCTAssertEqual(GridAxis.award("ring").displayLabel, "Champion")
        XCTAssertEqual(GridAxis.award("allNba").displayLabel, "All-NBA")
    }
}
