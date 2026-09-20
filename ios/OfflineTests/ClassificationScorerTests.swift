import XCTest
@testable import BasketballOffline

final class ClassificationScorerTests: XCTestCase {

    private func completed(mode: ClassificationMode, labels: [String],
                           subjects: [GameEntityRecord],
                           assignments: [String: Int]) -> ClassificationState {
        let def = ClassificationDefinition(
            id: "t", title: "T",
            config: ClassificationConfig(mode: mode, labels: labels,
                                         subjectCount: subjects.count, candidatePoolSize: 100))
        return ClassificationState(definition: def, subjects: subjects,
                                   assignments: assignments, status: .complete)
    }

    private func abc() -> [GameEntityRecord] {
        [GameTestFixtures.ent("a", rating: 9),
         GameTestFixtures.ent("b", rating: 5),
         GameTestFixtures.ent("c", rating: 1)]
    }

    func testTotalOrderPerfectMatchIs100() {
        let s = completed(mode: .totalOrder, labels: [], subjects: abc(),
                          assignments: ["a": 0, "b": 1, "c": 2])
        XCTAssertEqual(ClassificationScorer.score(s), 100)
    }

    func testTotalOrderFullyReversedIs0() {
        let s = completed(mode: .totalOrder, labels: [], subjects: abc(),
                          assignments: ["a": 2, "b": 1, "c": 0])
        XCTAssertEqual(ClassificationScorer.score(s), 0)
    }

    func testTotalOrderOneSwapIsPartial() {
        let s = completed(mode: .totalOrder, labels: [], subjects: abc(),
                          assignments: ["a": 1, "b": 0, "c": 2])
        XCTAssertEqual(ClassificationScorer.score(s), 67)
    }

    func testUniqueLabelsPerfectIs100() {
        let s = completed(mode: .uniqueLabels, labels: ["START", "BENCH", "CUT"],
                          subjects: abc(), assignments: ["a": 0, "b": 1, "c": 2])
        XCTAssertEqual(ClassificationScorer.score(s), 100)
    }

    // R7: same non-perfect permutation scores identically in totalOrder & uniqueLabels
    // (proves uniqueLabels isn't hard-coded to 100).
    func testUniqueLabelsNonPerfectMatchesOrderScore() {
        let assign = ["a": 1, "b": 0, "c": 2]   // one swap
        let order = completed(mode: .totalOrder, labels: [], subjects: abc(), assignments: assign)
        let labels = completed(mode: .uniqueLabels, labels: ["X", "Y", "Z"], subjects: abc(), assignments: assign)
        XCTAssertEqual(ClassificationScorer.score(order), ClassificationScorer.score(labels))
        XCTAssertEqual(ClassificationScorer.score(labels), 67)
    }

    func testTiersPerfectBandMatchIs100() {
        let subs = [GameTestFixtures.ent("a", rating: 9),
                    GameTestFixtures.ent("b", rating: 7),
                    GameTestFixtures.ent("c", rating: 3),
                    GameTestFixtures.ent("d", rating: 1)]
        let s = completed(mode: .tiers, labels: ["S", "A"], subjects: subs,
                          assignments: ["a": 0, "b": 0, "c": 1, "d": 1])
        XCTAssertEqual(ClassificationScorer.score(s), 100)
    }

    func testTiersOffByOneTierIsPartialNotZero() {
        let subs = [GameTestFixtures.ent("a", rating: 9),
                    GameTestFixtures.ent("b", rating: 7),
                    GameTestFixtures.ent("c", rating: 3),
                    GameTestFixtures.ent("d", rating: 1)]
        let s = completed(mode: .tiers, labels: ["S", "A"], subjects: subs,
                          assignments: ["a": 1, "b": 0, "c": 1, "d": 1])
        XCTAssertEqual(ClassificationScorer.score(s), 75)
    }

    // R7: 3 tiers so an adjacent-tier error earns real partial credit (0.5),
    // impossible to see with 2 tiers where adjacent == max distance.
    func testTiersThreeTierAdjacentEarnsHalf() {
        // 3 subjects, 3 tiers → model tiers a=0, b=1, c=2. Put a in tier 1 (adjacent).
        let subs = [GameTestFixtures.ent("a", rating: 9),
                    GameTestFixtures.ent("b", rating: 5),
                    GameTestFixtures.ent("c", rating: 1)]
        let s = completed(mode: .tiers, labels: ["S", "A", "B"], subjects: subs,
                          assignments: ["a": 1, "b": 1, "c": 2])
        // a: dist 1 → 1 - 1/2 = 0.5; b: dist 0 → 1; c: dist 0 → 1. avg = 2.5/3 = 0.833 → 83.
        XCTAssertEqual(ClassificationScorer.score(s), 83)
    }

    // R7: uneven bucketing pin — n=5, tiers=3 → model bands [0,0,1,1,2].
    func testTiersUnevenBucketingPerfect() {
        let subs = [GameTestFixtures.ent("a", rating: 9),
                    GameTestFixtures.ent("b", rating: 7),
                    GameTestFixtures.ent("c", rating: 5),
                    GameTestFixtures.ent("d", rating: 3),
                    GameTestFixtures.ent("e", rating: 1)]
        let s = completed(mode: .tiers, labels: ["S", "A", "B"], subjects: subs,
                          assignments: ["a": 0, "b": 0, "c": 1, "d": 1, "e": 2])
        XCTAssertEqual(ClassificationScorer.score(s), 100)
    }

    func testIncompleteStateScoresZero() {
        let s = ClassificationState(
            definition: ClassificationDefinition(
                id: "t", title: "T",
                config: ClassificationConfig(mode: .totalOrder, labels: [],
                                             subjectCount: 3, candidatePoolSize: 30)),
            subjects: abc(), assignments: ["a": 0], status: .assigning)
        XCTAssertEqual(ClassificationScorer.score(s), 0)
    }

    // R5: forged complete bijective state with duplicate destinations scores 0.
    func testMalformedBijectiveDuplicateDestinationScoresZero() {
        let s = completed(mode: .totalOrder, labels: [], subjects: abc(),
                          assignments: ["a": 0, "b": 0, "c": 2])   // two at dest 0
        XCTAssertEqual(ClassificationScorer.score(s), 0)
    }
}
