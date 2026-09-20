import XCTest
@testable import BasketballOffline

final class CompareConfigTests: XCTestCase {

    func testMetricValueReadsTheRightField() {
        let e = GameEntityRecord(id: "x", name: "X", team: "A", position: "PG",
                                 salary: 20_000_000, rating: 7,
                                 offRating: 4, defRating: 3, minutes: 32)
        XCTAssertEqual(CompareMetric.overall.value(e), 7)
        XCTAssertEqual(CompareMetric.offense.value(e), 4)
        XCTAssertEqual(CompareMetric.defense.value(e), 3)
        XCTAssertEqual(CompareMetric.salary.value(e), 20_000_000)
        XCTAssertEqual(CompareMetric.minutes.value(e), 32)
    }

    func testMetricValueNilWhenAbsent() {
        let e = GameTestFixtures.ent("x", rating: 5)   // no off/def/minutes
        XCTAssertNil(CompareMetric.offense.value(e))
        XCTAssertNil(CompareMetric.minutes.value(e))
        XCTAssertEqual(CompareMetric.overall.value(e), 5)
    }

    func testFormat() {
        let e = GameEntityRecord(id: "x", name: "X", team: "A", position: "PG",
                                 salary: 20_000_000, rating: 7.25,
                                 offRating: nil, defRating: nil, minutes: 31.6)
        XCTAssertEqual(CompareMetric.salary.format(e), "$20M")
        XCTAssertEqual(CompareMetric.minutes.format(e), "31.6 mpg")
        XCTAssertEqual(CompareMetric.overall.format(e), "+7.2")
    }

    func testCodableRoundtrip() throws {
        let def = CompareDefinition(id: "t", title: "T",
                                    config: CompareConfig(metric: .salary, direction: .higher))
        let back = try JSONDecoder().decode(CompareDefinition.self,
                                            from: JSONEncoder().encode(def))
        XCTAssertEqual(def, back)
    }
}
