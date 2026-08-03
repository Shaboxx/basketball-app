import Foundation

/// Pure gate for the footer Trade cell: Begin is enabled only once at least two
/// teams are selected (mirrors TradeSelectionState.canBegin's threshold).
nonisolated enum TradeCellLogic {
    static func beginEnabled(selectedCount: Int) -> Bool { selectedCount >= 2 }
}
