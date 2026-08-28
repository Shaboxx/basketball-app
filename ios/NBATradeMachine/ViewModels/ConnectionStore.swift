import Foundation
import SwiftUI
import Combine

/// Drives one CONNECTION session. Created per-session by the view over a
/// `ConnectionState` built by `ConnectionEngine.initialize`, holding the graph for
/// link validation. Wraps the pure state behind a Phase machine; `appendLink`
/// catches `ConnectionError` into `@Published lastError`.
@MainActor
final class ConnectionStore: ObservableObject {

    enum Phase: Equatable {
        case building
        case finished(Int)   // optimality score
    }

    @Published private(set) var state: ConnectionState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: ConnectionError?

    /// The graph is captured for `appendLink` validation. It's a pure Sendable
    /// value, so retaining it on the store is safe.
    private let graph: TeammateGraph

    init(state: ConnectionState, graph: TeammateGraph) {
        self.state = state
        self.graph = graph
        self.phase = state.status == .complete ? .finished(state.score) : .building
    }

    nonisolated deinit {}

    /// Append one teammate link. On success advances the chain; on failure latches
    /// `lastError` (transient — the UI shows it and lets the player retry).
    func appendLink(playerId: String) {
        guard case .building = phase else { return }
        do {
            let next = try ConnectionEngine.appendLink(state, playerId: playerId, graph: graph)
            state = next
            lastError = nil
            if next.status == .complete { phase = .finished(next.score) }
        } catch let error as ConnectionError {
            lastError = error
        } catch {
            lastError = .notTeammate
        }
    }

    /// Step the chain back one link (remove the last interior node). Recovers from a
    /// dead-end without abandoning progress; latches `.nothingToUndo` at `[startId]`.
    func undo() {
        guard case .building = phase else { return }
        do {
            state = try ConnectionEngine.undoLastLink(state)
            lastError = nil
        } catch let error as ConnectionError {
            lastError = error
        } catch {
            lastError = .nothingToUndo
        }
    }

    /// Restart the SAME puzzle: return the chain to `[startId]` (endpoints preserved).
    /// Always recovers from any dead-end. Clears the phase back to `.building`.
    func reset() {
        state = ConnectionEngine.reset(state)
        phase = .building
        lastError = nil
    }

    func clearError() { lastError = nil }
}
