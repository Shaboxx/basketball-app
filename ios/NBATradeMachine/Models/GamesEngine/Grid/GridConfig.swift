import Foundation

/// The axis FAMILIES a grid preset may draw its 6 headers from. The engine
/// enumerates concrete `GridAxis` values of each enabled family from the pool
/// (e.g. `.axisFamilies = [.franchise, .decade]` ⇒ headers are franchises and
/// decades that actually occur in the pool). Sol's first-ship palette:
/// franchise + decade + positionFamily + broad awards; MVP & stat-thresholds are
/// DEFERRED (sparse intersections break always-solvable generation).
nonisolated enum GridAxisFamily: String, Codable, Equatable, CaseIterable {
    case franchise, decade, positionFamily, award
}

/// A GRID preset — presets-as-data. `rows`/`cols` are pinned to 3. `axisFamilies`
/// declares which header families the engine may draw from. `minCellAnswers` is
/// the always-solvable floor every one of the 9 cells must clear before the grid
/// is presented (default 1). `rarityScaling` scales the 100/count base score.
nonisolated struct GridDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let axisFamilies: [GridAxisFamily]
    let rows: Int
    let cols: Int
    let minCellAnswers: Int
    let rarityScaling: Double

    init(id: String, title: String, axisFamilies: [GridAxisFamily],
         rows: Int = 3, cols: Int = 3, minCellAnswers: Int = 1,
         rarityScaling: Double = 1.0) {
        self.id = id
        self.title = title
        self.axisFamilies = axisFamilies
        self.rows = rows
        self.cols = cols
        self.minCellAnswers = minCellAnswers
        self.rarityScaling = rarityScaling
    }
}

/// A grid cell address (row/col index 0..<3). Codable/Hashable so it keys the
/// fill dictionary and survives a Codable round-trip of the whole state.
/// `Identifiable` (id = "row,col") so it can drive a SwiftUI `sheet(item:)`.
nonisolated struct GridCell: Codable, Equatable, Hashable, Identifiable {
    let row: Int
    let col: Int
    var id: String { "\(row),\(col)" }
}

/// A completed cell fill — which distinct player answered, and the rarity points
/// earned. Stored per cell in the state.
nonisolated struct GridFillResult: Codable, Equatable {
    let playerId: String
    let playerName: String
    let points: Int
}
