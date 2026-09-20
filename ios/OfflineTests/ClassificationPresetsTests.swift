import XCTest
@testable import BasketballOffline

final class ClassificationPresetsTests: XCTestCase {

    func testUnknownIdNil() {
        XCTAssertNil(ClassificationPresets.definition(for: "no-such"))
    }

    func testRankPreset() throws {
        let d = try XCTUnwrap(ClassificationPresets.definition(for: "rank-players"))
        XCTAssertEqual(d.config.mode, .totalOrder)
        XCTAssertEqual(d.config.subjectCount, 8)
    }

    func testTierListPreset() throws {
        let d = try XCTUnwrap(ClassificationPresets.definition(for: "tier-list"))
        XCTAssertEqual(d.config.mode, .tiers)
        XCTAssertEqual(d.config.labels, ["S", "A", "B", "C", "D"])
    }

    func testStartBenchCutPreset() throws {
        let d = try XCTUnwrap(ClassificationPresets.definition(for: "start-bench-cut"))
        XCTAssertEqual(d.config.mode, .uniqueLabels)
        XCTAssertEqual(d.config.labels, ["START", "BENCH", "CUT"])
        XCTAssertEqual(d.config.subjectCount, 3)
    }

    func testPresetIdsAreRegistryCards() {
        for id in ["rank-players", "tier-list", "start-bench-cut"] {
            XCTAssertNotNil(DraftGameRegistry.game(id), "missing card: \(id)")
        }
    }
}
