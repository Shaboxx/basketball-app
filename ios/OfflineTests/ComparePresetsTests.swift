import XCTest
@testable import BasketballOffline

final class ComparePresetsTests: XCTestCase {

    func testUnknownIdNil() {
        XCTAssertNil(ComparePresets.definition(for: "no-such"))
    }

    func testBiggerContractPreset() throws {
        let d = try XCTUnwrap(ComparePresets.definition(for: "bigger-contract"))
        XCTAssertEqual(d.config.metric, .salary)
        XCTAssertEqual(d.config.direction, .higher)
    }

    func testHigherRatedPreset() throws {
        let d = try XCTUnwrap(ComparePresets.definition(for: "higher-rated"))
        XCTAssertEqual(d.config.metric, .overall)
        XCTAssertEqual(d.config.direction, .higher)
    }

    func testPresetIdsAreRegistryCards() {
        for id in ["bigger-contract", "higher-rated"] {
            XCTAssertNotNil(DraftGameRegistry.game(id), "missing card: \(id)")
        }
    }
}
