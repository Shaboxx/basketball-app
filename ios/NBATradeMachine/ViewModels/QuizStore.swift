import Foundation
import SwiftUI
import Combine

/// Drives one QUIZ session. Created per-session by the launching view.
@MainActor
final class QuizStore: ObservableObject {

    enum Phase: Equatable {
        case answering
        case finished(Int)   // final correct count
    }

    @Published private(set) var state: QuizState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: QuizError?

    init(state: QuizState) {
        self.state = state
        self.phase = state.status == .complete ? .finished(state.score) : .answering
    }

    // See GameSetupStore: default-MainActor deinit trips a double-free under XCTest.
    nonisolated deinit {}

    func answer(choiceIndex: Int) {
        guard case .answering = phase else { return }
        do {
            state = try QuizEngine.answer(state, choiceIndex: choiceIndex)
            lastError = nil
            if state.status == .complete { phase = .finished(state.score) }
        } catch let e as QuizError {
            lastError = e
        } catch {
            lastError = nil
        }
    }

    func clearError() { lastError = nil }
}
