import XCTest
@testable import BasketballOffline

/// Phase-6 T5: preset ids match the registry, families are correct, and unknown
/// ids return nil.
final class GridPresetsTests: XCTestCase {

    func testImmaculateGridPreset() {
        let def = GridPresets.definition(for: "immaculate-grid")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.id, "immaculate-grid")
        XCTAssertEqual(def?.rows, 3)
        XCTAssertEqual(def?.cols, 3)
        XCTAssertEqual(def?.axisFamilies, [.franchise, .decade, .positionFamily, .award])
    }

    func testFranchiseGridPreset() {
        let def = GridPresets.definition(for: "franchise-grid")
        XCTAssertEqual(def?.id, "franchise-grid")
        XCTAssertEqual(def?.axisFamilies, [.franchise])
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(GridPresets.definition(for: "no-such-grid"))
    }

    func testPresetIdsMatchRegistryCards() {
        let ids = Set(DraftGameRegistry.all.map { $0.id })
        XCTAssertTrue(ids.contains(GridPresets.immaculateGridId))
        XCTAssertTrue(ids.contains(GridPresets.franchiseGridId))
    }

    func testRegistryCardsAreSinglePlayer() {
        for id in ["immaculate-grid", "franchise-grid"] {
            let game = DraftGameRegistry.game(id)
            XCTAssertEqual(game?.capabilities.maxParticipants, 1)
            XCTAssertEqual(game?.capabilities.allowsCPU, false)
        }
    }
}
