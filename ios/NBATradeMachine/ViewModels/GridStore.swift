import Foundation
import SwiftUI
import Combine

/// Drives one GRID session. Created per-session by the view over a `GridState`
/// built by `GridEngine.initialize`. Wraps the pure state behind a Phase machine;
/// intents catch `GridError` into `@Published lastError` for the UI to surface.
@MainActor
final class GridStore: ObservableObject {

    enum Phase: Equatable {
        case filling
        case finished(Int)   // final rarity total
    }

    @Published private(set) var state: GridState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: GridError?
    /// The cell the player is currently answering (drives the search sheet).
    @Published var selectedCell: GridCell?

    init(state: GridState) {
        self.state = state
        self.phase = state.status == .complete ? .finished(state.score) : .filling
    }

    nonisolated deinit {}

    /// Submit a distinct player for the currently selected (or an explicit) cell.
    /// On success advances the state; on failure latches `lastError` (transient).
    func submitAnswer(cell: GridCell, playerId: String) {
        guard case .filling = phase else { return }
        do {
            let next = try GridEngine.submitAnswer(state, cell: cell, playerId: playerId)
            state = next
            lastError = nil
            selectedCell = nil
            if next.status == .complete { phase = .finished(next.score) }
        } catch let error as GridError {
            lastError = error
        } catch {
            lastError = .doesNotSatisfy
        }
    }

    func selectCell(_ cell: GridCell) {
        guard case .filling = phase, state.cellFills[cell] == nil else { return }
        selectedCell = cell
    }

    func clearError() { lastError = nil }
}
