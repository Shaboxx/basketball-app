import Foundation

/// GRID presets — presets-as-data. Ids MUST equal `DraftGameRegistry` card ids.
/// Ships Sol's approved axis-family palette (franchise + decade + positionFamily +
/// broad awards; MVP & stat-thresholds deferred).
nonisolated enum GridPresets {

    static let immaculateGridId = "immaculate-grid"
    static let franchiseGridId = "franchise-grid"

    static func definition(for gameId: String) -> GridDefinition? {
        switch gameId {
        case Self.immaculateGridId: return immaculateGrid
        case Self.franchiseGridId:  return franchiseGrid
        default:                    return nil
        }
    }

    /// Mixed-axis grid: franchise × decade × award × positionFamily headers.
    static var immaculateGrid: GridDefinition {
        GridDefinition(id: Self.immaculateGridId, title: "Immaculate Grid",
                       axisFamilies: [.franchise, .decade, .positionFamily, .award])
    }

    /// All-franchise variant: every header is "played for TEAM".
    static var franchiseGrid: GridDefinition {
        GridDefinition(id: Self.franchiseGridId, title: "Franchise Grid",
                       axisFamilies: [.franchise])
    }
}
