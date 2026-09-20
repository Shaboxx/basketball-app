import XCTest
@testable import BasketballOffline

final class ClassificationConfigTests: XCTestCase {

    func testBijectiveModes() {
        XCTAssertTrue(ClassificationMode.totalOrder.isBijective)
        XCTAssertTrue(ClassificationMode.uniqueLabels.isBijective)
        XCTAssertFalse(ClassificationMode.tiers.isBijective)
    }

    func testDestinationCountTotalOrderEqualsSubjects() {
        let c = ClassificationConfig(mode: .totalOrder, labels: [],
                                     subjectCount: 8, candidatePoolSize: 40)
        XCTAssertEqual(c.destinationCount, 8)
    }

    func testDestinationCountTiersEqualsLabels() {
        let c = ClassificationConfig(mode: .tiers, labels: ["S", "A", "B", "C", "D"],
                                     subjectCount: 12, candidatePoolSize: 60)
        XCTAssertEqual(c.destinationCount, 5)
    }

    func testDestinationLabelTotalOrderIsRankNumber() {
        let c = ClassificationConfig(mode: .totalOrder, labels: [],
                                     subjectCount: 3, candidatePoolSize: 30)
        XCTAssertEqual(c.destinationLabel(0), "1")
        XCTAssertEqual(c.destinationLabel(2), "3")
    }

    func testDestinationLabelTiersUsesLabels() {
        let c = ClassificationConfig(mode: .tiers, labels: ["S", "A", "B"],
                                     subjectCount: 6, candidatePoolSize: 30)
        XCTAssertEqual(c.destinationLabel(0), "S")
        XCTAssertEqual(c.destinationLabel(2), "B")
    }

    func testCodableRoundtrip() throws {
        let def = ClassificationDefinition(
            id: "t", title: "T",
            config: ClassificationConfig(mode: .uniqueLabels,
                                         labels: ["START", "BENCH", "CUT"],
                                         subjectCount: 3, candidatePoolSize: 30))
        let back = try JSONDecoder().decode(ClassificationDefinition.self,
                                            from: JSONEncoder().encode(def))
        XCTAssertEqual(def, back)
    }
}
