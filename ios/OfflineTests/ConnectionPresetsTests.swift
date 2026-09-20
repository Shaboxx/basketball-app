import XCTest
@testable import BasketballOffline

/// Phase-6 T8: six-degrees preset id/fields + registry match.
final class ConnectionPresetsTests: XCTestCase {

    func testSixDegreesPreset() {
        let def = ConnectionPresets.definition(for: "six-degrees")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.id, "six-degrees")
        XCTAssertEqual(def?.scoreMode, .optimality)
        XCTAssertEqual(def?.targetDistanceMin, 2)
        XCTAssertEqual(def?.targetDistanceMax, 4)
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(ConnectionPresets.definition(for: "no-such"))
    }

    func testPresetIdMatchesRegistryCard() {
        let ids = Set(DraftGameRegistry.all.map { $0.id })
        XCTAssertTrue(ids.contains(ConnectionPresets.sixDegreesId))
        let game = DraftGameRegistry.game("six-degrees")
        XCTAssertEqual(game?.capabilities.maxParticipants, 1)
        XCTAssertEqual(game?.capabilities.allowsCPU, false)
    }
}
