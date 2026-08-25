import Foundation
import SwiftUI
import Combine

/// Drives one compare (Higher/Lower) session. Created per-session by the view.
@MainActor
final class CompareStore: ObservableObject {

    enum Phase: Equatable {
        case guessing
        case finished(Int)   // final streak
    }

    @Published private(set) var state: CompareState
    @Published private(set) var phase: Phase

    init(state: CompareState) {
        self.state = state
        self.phase = state.status == .complete ? .finished(state.score) : .guessing
    }

    nonisolated deinit {}

    func guess(subjectId: String) {
        guard case .guessing = phase else { return }
        guard let next = try? CompareEngine.guess(state, subjectId: subjectId) else { return }
        state = next
        if next.status == .complete { phase = .finished(next.score) }
    }
}
