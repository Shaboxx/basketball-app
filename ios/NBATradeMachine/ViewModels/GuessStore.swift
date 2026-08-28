import Foundation
import SwiftUI
import Combine

/// Drives one GUESS session. Created per-session by the launching view.
@MainActor
final class GuessStore: ObservableObject {

    enum Phase: Equatable {
        case guessing
        case finished(Int)   // final score (0…100)
    }

    @Published private(set) var state: GuessState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: GuessError?

    init(state: GuessState) {
        self.state = state
        self.phase = state.status == .active
            ? .guessing : .finished(GuessEngine.score(state))
    }

    // See GameSetupStore: default-MainActor deinit trips a double-free under XCTest.
    nonisolated deinit {}

    /// Reveal the next clue (costs points on the ladder). Silently no-ops when the
    /// game is finished; surfaces a typed error if there are no more clues.
    func revealClue() {
        guard case .guessing = phase else { return }
        do {
            state = try GuessEngine.revealNextClue(state)
            lastError = nil
        } catch let e as GuessError {
            lastError = e
        } catch {
            lastError = nil
        }
    }

    /// Submit a guess (a pool entity id). Wins/loses transition to `.finished`.
    func guess(subjectId: String) {
        guard case .guessing = phase else { return }
        do {
            state = try GuessEngine.guess(state, subjectId: subjectId)
            lastError = nil
            if state.status != .active {
                phase = .finished(GuessEngine.score(state))
            }
        } catch let e as GuessError {
            lastError = e
        } catch {
            lastError = nil
        }
    }

    func clearError() { lastError = nil }
}
