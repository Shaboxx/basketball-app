import XCTest
@testable import BasketballOffline

final class FeasibilitySeededRosterTests: XCTestCase {

    func testSeededRosterEmptyDefaultMatchesUnseeded() {
        // Default seededRoster ([]) must behave exactly like before.
        let slots = RosterConfig.positionless(2).slots
        let pool = GameTestFixtures.tenManPool()
        XCTAssertNotNil(GameFeasibility.fill(slots: slots, from: pool, constraints: []))
        XCTAssertNotNil(GameFeasibility.fill(slots: slots, from: pool, constraints: [],
                                             economy: nil, seededRoster: []))
    }

    func testSeededTeamMakesUniqueByInfeasible() {
        // uniqueBy(.team): 1 slot, pool has only a DEN player, and the seed
        // already holds a DEN player → no distinct-team candidate → nil.
        let slots = RosterConfig.positionless(1).slots
        let pool = [GameTestFixtures.ent("den2", team: "DEN")]
        let seed = [GameTestFixtures.ent("den1", team: "DEN")]
        XCTAssertNil(GameFeasibility.fill(slots: slots, from: pool,
                                          constraints: [.uniqueBy(.team)],
                                          seededRoster: seed))
    }

    func testSeededTeamAllowsDistinctTeamCandidate() {
        // Same shape but the pool player is on a DIFFERENT team → fillable.
        let slots = RosterConfig.positionless(1).slots
        let pool = [GameTestFixtures.ent("bos1", team: "BOS")]
        let seed = [GameTestFixtures.ent("den1", team: "DEN")]
        XCTAssertNotNil(GameFeasibility.fill(slots: slots, from: pool,
                                             constraints: [.uniqueBy(.team)],
                                             seededRoster: seed))
    }

    func testSeededRosterNotChargedAgainstBudget() {
        // Budget covers ONLY the slot being filled (the seeded player's cost is
        // already spent). 1 slot, budget $5M, seed is a $50M player, pool has a
        // $3M player → fillable because the seed isn't re-charged.
        let slots = RosterConfig.positionless(1).slots
        let pool = [GameTestFixtures.ent("cheap", salary: 3_000_000)]
        let seed = [GameTestFixtures.ent("star", salary: 50_000_000)]
        let econ = EconomyConfig(pricingMethod: .databaseValue, startingBudget: 5_000_000)
        XCTAssertNotNil(GameFeasibility.fill(slots: slots, from: pool, constraints: [],
                                             economy: econ, seededRoster: seed))
    }
}
