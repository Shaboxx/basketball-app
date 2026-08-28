import Foundation
import SwiftUI
import Combine

/// Drives one BRACKET session. Created per-session by the launching view (like
/// CompareStore / ClassificationStore), so it is NOT injected at the app root.
@MainActor
final class BracketStore: ObservableObject {

    enum Phase: Equatable {
        case choosing(matchupIndex: Int)
        case finished(BracketResult)
    }

    @Published private(set) var state: BracketState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: BracketError?

    init(state: BracketState) {
        self.state = state
        self.phase = Self.phase(for: state)
    }

    // See GameSetupStore / ClassificationStore: default-MainActor isolated deinit
    // trips a task-local double-free under XCTest — keep it nonisolated.
    nonisolated deinit {}

    /// Advance the current matchup by picking `winnerId`. On success updates state
    /// + phase; on a typed engine error records `lastError` and leaves state
    /// unchanged so the view can surface the rejection.
    func advance(winnerId: String) {
        guard case .choosing = phase else { return }
        do {
            state = try BracketEngine.advance(state, winnerId: winnerId)
            lastError = nil
            phase = Self.phase(for: state)
        } catch let e as BracketError {
            lastError = e
        } catch {
            lastError = .outOfOrder
        }
    }

    /// Dismiss a surfaced rejection (mirrors GameSessionStore / ClassificationStore).
    func clearError() { lastError = nil }

    private static func phase(for state: BracketState) -> Phase {
        if let idx = BracketEngine.currentMatchupIndex(state) {
            return .choosing(matchupIndex: idx)
        }
        return .finished(BracketScorer.buildResult(state))
    }
}
