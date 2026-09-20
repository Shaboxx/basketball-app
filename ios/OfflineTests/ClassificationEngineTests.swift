import XCTest
@testable import BasketballOffline

final class ClassificationEngineTests: XCTestCase {

    private func subjectsPool() -> [GameEntityRecord] {
        (0..<30).map { GameTestFixtures.ent("p\($0)", rating: Double($0)) }
    }

    private func start(mode: ClassificationMode, labels: [String],
                       count: Int) throws -> ClassificationState {
        let def = ClassificationDefinition(
            id: "t", title: "T",
            config: ClassificationConfig(mode: mode, labels: labels,
                                         subjectCount: count, candidatePoolSize: 30))
        return try ClassificationEngine.initialize(definition: def,
                                                   pool: subjectsPool(), seed: 1)
    }

    func testInitializePicksSubjectsAndStartsUnassigned() throws {
        let state = try start(mode: .totalOrder, labels: [], count: 5)
        XCTAssertEqual(state.subjects.count, 5)
        XCTAssertTrue(state.assignments.isEmpty)
        XCTAssertEqual(state.status, .assigning)
    }

    func testInitializeThrowsWhenNotEnoughSubjects() {
        let def = ClassificationDefinition(
            id: "t", title: "T",
            config: ClassificationConfig(mode: .uniqueLabels, labels: ["A", "B", "C"],
                                         subjectCount: 3, candidatePoolSize: 30))
        XCTAssertThrowsError(try ClassificationEngine.initialize(
            definition: def, pool: Array(subjectsPool().prefix(2)), seed: 1)) {
            XCTAssertEqual($0 as? ClassificationError, .notEnoughSubjects)
        }
    }

    func testInitializeThrowsUniqueLabelsCountMismatch() {
        let def = ClassificationDefinition(
            id: "t", title: "T",
            config: ClassificationConfig(mode: .uniqueLabels, labels: ["A", "B", "C"],
                                         subjectCount: 4, candidatePoolSize: 30))
        XCTAssertThrowsError(try ClassificationEngine.initialize(
            definition: def, pool: subjectsPool(), seed: 1)) {
            XCTAssertEqual($0 as? ClassificationError, .invalidConfig)
        }
    }

    // R2: nonpositive counts and empty labels are invalidConfig, not traps.
    func testInitializeRejectsNonpositiveAndEmptyLabels() {
        func def(mode: ClassificationMode, labels: [String], count: Int, pool: Int) -> ClassificationDefinition {
            ClassificationDefinition(id: "t", title: "T",
                config: ClassificationConfig(mode: mode, labels: labels,
                                             subjectCount: count, candidatePoolSize: pool))
        }
        let pool = subjectsPool()
        for d in [def(mode: .totalOrder, labels: [], count: 0, pool: 30),
                  def(mode: .totalOrder, labels: [], count: -1, pool: 30),
                  def(mode: .totalOrder, labels: [], count: 5, pool: -1),
                  def(mode: .tiers, labels: [], count: 5, pool: 30),
                  def(mode: .uniqueLabels, labels: [], count: 3, pool: 30)] {
            XCTAssertThrowsError(try ClassificationEngine.initialize(definition: d, pool: pool, seed: 1)) {
                XCTAssertEqual($0 as? ClassificationError, .invalidConfig)
            }
        }
    }

    func testAssignTiersAllowsReuse() throws {
        var state = try start(mode: .tiers, labels: ["S", "A", "B"], count: 4)
        let ids = state.subjects.map(\.id)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 0)
        state = try ClassificationEngine.assign(state, subjectId: ids[1], destination: 0)
        XCTAssertEqual(state.assignments[ids[0]], 0)
        XCTAssertEqual(state.assignments[ids[1]], 0)
    }

    func testAssignBijectiveRejectsTakenDestination() throws {
        var state = try start(mode: .totalOrder, labels: [], count: 3)
        let ids = state.subjects.map(\.id)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 0)
        XCTAssertThrowsError(try ClassificationEngine.assign(state, subjectId: ids[1], destination: 0)) {
            XCTAssertEqual($0 as? ClassificationError, .destinationTaken)
        }
    }

    func testReassigningSameSubjectMovesIt() throws {
        var state = try start(mode: .totalOrder, labels: [], count: 3)
        let ids = state.subjects.map(\.id)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 0)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 1)
        XCTAssertEqual(state.assignments[ids[0]], 1)
        state = try ClassificationEngine.assign(state, subjectId: ids[1], destination: 0)
        XCTAssertEqual(state.assignments[ids[1]], 0)
    }

    func testUnknownSubjectAndOutOfRangeThrow() throws {
        let state = try start(mode: .totalOrder, labels: [], count: 3)
        XCTAssertThrowsError(try ClassificationEngine.assign(state, subjectId: "nope", destination: 0)) {
            XCTAssertEqual($0 as? ClassificationError, .unknownSubject)
        }
        XCTAssertThrowsError(try ClassificationEngine.assign(state, subjectId: state.subjects[0].id, destination: 3)) {
            XCTAssertEqual($0 as? ClassificationError, .invalidDestination)
        }
    }

    func testCompletesWhenAllAssigned() throws {
        var state = try start(mode: .uniqueLabels, labels: ["A", "B", "C"], count: 3)
        let ids = state.subjects.map(\.id)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 0)
        state = try ClassificationEngine.assign(state, subjectId: ids[1], destination: 1)
        XCTAssertEqual(state.status, .assigning)
        state = try ClassificationEngine.assign(state, subjectId: ids[2], destination: 2)
        XCTAssertEqual(state.status, .complete)
    }

    // R4: no assigns after completion.
    func testAssignAfterCompletionThrows() throws {
        var state = try start(mode: .uniqueLabels, labels: ["A", "B", "C"], count: 3)
        let ids = state.subjects.map(\.id)
        state = try ClassificationEngine.assign(state, subjectId: ids[0], destination: 0)
        state = try ClassificationEngine.assign(state, subjectId: ids[1], destination: 1)
        state = try ClassificationEngine.assign(state, subjectId: ids[2], destination: 2)
        XCTAssertThrowsError(try ClassificationEngine.assign(state, subjectId: ids[0], destination: 1)) {
            XCTAssertEqual($0 as? ClassificationError, .alreadyComplete)
        }
    }
}
