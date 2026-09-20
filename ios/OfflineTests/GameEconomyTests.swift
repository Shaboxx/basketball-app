import XCTest
@testable import BasketballOffline

final class GameEconomyTests: XCTestCase {

    func testDatabaseValuePricesBySalary() {
        let econ = EconomyConfig(pricingMethod: .databaseValue, startingBudget: 100)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("a", salary: 55_000_000)), 55_000_000)
    }

    func testDatabaseValueMissingSalaryIsZero() {
        let econ = EconomyConfig(pricingMethod: .databaseValue, startingBudget: 100)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("a", salary: nil)), 0)
    }

    func testDatabaseValueNegativeSalaryClampsToZero() {
        let econ = EconomyConfig(pricingMethod: .databaseValue, startingBudget: 100)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("a", salary: -5)), 0)
    }

    func testTierPriceBucketsMonotonicallyByRating() {
        let econ = EconomyConfig(pricingMethod: .tierPrice, startingBudget: 15)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("a", rating: 9)), 6)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("b", rating: 5)), 5)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("c", rating: 3)), 4)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("d", rating: 1)), 3)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("e", rating: -1)), 2)
        XCTAssertEqual(econ.price(GameTestFixtures.ent("f", rating: -3)), 1)
    }

    func testTierPriceIsMonotoneNonDecreasing() {
        let econ = EconomyConfig(pricingMethod: .tierPrice, startingBudget: 15)
        let prices = stride(from: -5.0, through: 10.0, by: 0.5)
            .map { econ.price(GameTestFixtures.ent("x", rating: $0)) }
        XCTAssertEqual(prices, prices.sorted())
    }

    func testCodableRoundtrip() throws {
        let econ = EconomyConfig(pricingMethod: .tierPrice, startingBudget: 15)
        let back = try JSONDecoder().decode(EconomyConfig.self,
                                            from: JSONEncoder().encode(econ))
        XCTAssertEqual(econ, back)
    }
}
