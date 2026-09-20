import XCTest
@testable import BasketballOffline

final class BracketPresetsTests: XCTestCase {

    func testUnknownIdHasNoPreset() {
        XCTAssertNil(BracketPresets.definition(for: "no-such-bracket"))
    }

    func testPresetIdsMatchRegistryCards() {
        for id in ["best-player-bracket", "position-bracket", "quick-bracket"] {
            XCTAssertNotNil(BracketPresets.definition(for: id), "no preset for \(id)")
            XCTAssertNotNil(DraftGameRegistry.game(id), "no registry card for \(id)")
        }
    }

    func testFieldSizesAndScoring() throws {
        let best = try XCTUnwrap(BracketPresets.definition(for: "best-player-bracket"))
        XCTAssertEqual(best.fieldSize, 16)
        XCTAssertTrue(best.seedByRating)
        XCTAssertEqual(best.scoring, .modelAgreement)

        let quick = try XCTUnwrap(BracketPresets.definition(for: "quick-bracket"))
        XCTAssertEqual(quick.fieldSize, 4)
        XCTAssertFalse(quick.seedByRating)
        XCTAssertEqual(quick.scoring, .none)
    }

    func testPresetsInitializeOnARealisticPool() throws {
        let pool = (0..<40).map {
            GameEntityRecord(id: "p\($0)", name: "P", team: "T\($0)", position: "PG",
                             salary: nil, rating: Double($0))
        }
        for id in ["best-player-bracket", "position-bracket", "quick-bracket"] {
            let def = BracketPresets.definition(for: id)!
            XCTAssertNoThrow(try BracketEngine.initialize(definition: def, pool: pool, seed: 1))
        }
    }
}
