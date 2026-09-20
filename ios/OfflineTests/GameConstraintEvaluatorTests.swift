import XCTest
@testable import BasketballOffline

final class GameConstraintEvaluatorTests: XCTestCase {

    func testFieldAccessReturnsTypedValues() {
        let e = GameTestFixtures.ent("jokic", pos: "C", team: "DEN",
                                     rating: 9.5, salary: 55_000_000)
        XCTAssertEqual(e.value(for: .team), .string("DEN"))
        XCTAssertEqual(e.value(for: .position), .string("C"))
        XCTAssertEqual(e.value(for: .rating), .number(9.5))
        XCTAssertEqual(e.value(for: .salary), .number(55_000_000))
    }

    func testMissingSalaryIsNil() {
        XCTAssertNil(GameTestFixtures.ent("x", salary: nil).value(for: .salary))
    }

    func testEntityCodableRoundtrip() throws {
        let e = GameTestFixtures.ent("jokic", pos: "C", team: "DEN", rating: 9.5)
        let back = try JSONDecoder().decode(GameEntityRecord.self,
                                            from: JSONEncoder().encode(e))
        XCTAssertEqual(e, back)
    }

    // MARK: entity-scope constraints

    private func fc(_ field: GameField, _ op: ConstraintOperator,
                    _ value: ConstraintValue) -> GameConstraint {
        .field(FieldConstraint(field: field, op: op, value: value))
    }

    func testFieldOperators() {
        let e = GameTestFixtures.ent("x", pos: "SG", team: "DEN",
                                     rating: 5, salary: 30_000_000)
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.team, .equal, .string("DEN"))))
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.team, .notEqual, .string("DEN"))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.position, .isIn, .strings(["PG", "SG"]))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.position, .notIn, .strings(["C"]))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.rating, .greaterThan, .number(4))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.rating, .greaterOrEqual, .number(5))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.salary, .lessThan, .number(40_000_000))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.salary, .lessOrEqual, .number(30_000_000))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, fc(.rating, .between, .range(min: 5, max: 6))))
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.rating, .between, .range(min: 5.1, max: 6))))
    }

    func testMissingFieldNeverSatisfies() {
        let e = GameTestFixtures.ent("x", salary: nil)
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.salary, .greaterThan, .number(0))))
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.salary, .lessThan, .number(1))))
    }

    func testNotOperatorsDivergeOnMissingData() {
        // Pinned contract: direct notEqual/notIn use missing-data-never-satisfies,
        // but the .not combinator is classical negation and flips that false.
        let e = GameTestFixtures.ent("x", salary: nil)
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.salary, .notEqual, .number(5))))
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, .not(fc(.salary, .equal, .number(5)))))
    }

    func testTypeMismatchNeverSatisfies() {
        let e = GameTestFixtures.ent("x", team: "DEN")
        XCTAssertFalse(GameConstraintEvaluator.satisfies(e, fc(.team, .greaterThan, .number(1))))
    }

    func testBooleanComposition() {
        let e = GameTestFixtures.ent("x", pos: "PG", team: "DEN", rating: 8)
        let c: GameConstraint = .and([
            fc(.rating, .greaterThan, .number(5)),
            .or([fc(.position, .equal, .string("PG")), fc(.position, .equal, .string("SG"))]),
            .not(fc(.team, .equal, .string("LAL"))),
        ])
        XCTAssertTrue(GameConstraintEvaluator.satisfies(e, c))
        let lal = GameTestFixtures.ent("y", pos: "PG", team: "LAL", rating: 8)
        XCTAssertFalse(GameConstraintEvaluator.satisfies(lal, c))
    }

    func testConstraintCodableRoundtrip() throws {
        let c: GameConstraint = .and([
            fc(.position, .isIn, .strings(["PG", "SG"])),
            .not(fc(.rating, .between, .range(min: 0, max: 2))),
        ])
        let back = try JSONDecoder().decode(GameConstraint.self,
                                            from: JSONEncoder().encode(c))
        XCTAssertEqual(c, back)
    }

    // MARK: roster-scope constraints

    func testUniqueByBlocksDuplicateTeam() {
        let roster = [GameTestFixtures.ent("a", team: "DEN")]
        let dup = GameTestFixtures.ent("b", team: "DEN")
        let other = GameTestFixtures.ent("c", team: "BOS")
        let cs: [RosterConstraint] = [.uniqueBy(.team)]
        XCTAssertFalse(GameConstraintEvaluator.allowsPick(roster: roster, candidate: dup, constraints: cs))
        XCTAssertTrue(GameConstraintEvaluator.allowsPick(roster: roster, candidate: other, constraints: cs))
    }

    func testMaxCountWhere() {
        let star = fc(.rating, .greaterThan, .number(8))
        let cs: [RosterConstraint] = [.maxCountWhere(star, 1)]
        let roster = [GameTestFixtures.ent("a", rating: 9)]
        XCTAssertFalse(GameConstraintEvaluator.allowsPick(
            roster: roster, candidate: GameTestFixtures.ent("b", rating: 9), constraints: cs))
        XCTAssertTrue(GameConstraintEvaluator.allowsPick(
            roster: roster, candidate: GameTestFixtures.ent("c", rating: 3), constraints: cs))
    }

    func testTotalAtMostIsInclusive() {
        let cs: [RosterConstraint] = [.totalAtMost(.salary, 50_000_000)]
        let roster = [GameTestFixtures.ent("a", salary: 30_000_000)]
        XCTAssertTrue(GameConstraintEvaluator.allowsPick(
            roster: roster, candidate: GameTestFixtures.ent("b", salary: 20_000_000), constraints: cs))
        XCTAssertFalse(GameConstraintEvaluator.allowsPick(
            roster: roster, candidate: GameTestFixtures.ent("c", salary: 20_000_001), constraints: cs))
    }

    func testMinCountWhereGatesCompletionNotPicks() {
        let big = fc(.position, .equal, .string("C"))
        let cs: [RosterConstraint] = [.minCountWhere(big, 1)]
        // Mid-draft: picking a guard is fine even with no center yet.
        XCTAssertTrue(GameConstraintEvaluator.allowsPick(
            roster: [], candidate: GameTestFixtures.ent("g", pos: "PG"), constraints: cs))
        // Completion: a roster with no center fails; with one passes.
        XCTAssertFalse(GameConstraintEvaluator.satisfiesCompleted(
            [GameTestFixtures.ent("g", pos: "PG")], constraints: cs))
        XCTAssertTrue(GameConstraintEvaluator.satisfiesCompleted(
            [GameTestFixtures.ent("c", pos: "C")], constraints: cs))
    }
}
