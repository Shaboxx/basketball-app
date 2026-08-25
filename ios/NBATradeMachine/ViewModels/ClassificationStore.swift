import Foundation
import SwiftUI
import Combine

/// Drives one classification session. Created per-session by the launching view.
@MainActor
final class ClassificationStore: ObservableObject {

    enum Phase: Equatable {
        case assigning
        case finished(Int)   // score 0–100
    }

    @Published private(set) var state: ClassificationState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: ClassificationError?

    init(state: ClassificationState) {
        self.state = state
        self.phase = state.status == .complete
            ? .finished(ClassificationScorer.score(state)) : .assigning
    }

    // See GameSetupStore: default-MainActor deinit trips a double-free under XCTest.
    nonisolated deinit {}

    /// Assign a subject to a destination. Returns true on success (R11) so the
    /// view can retain its pending selection when an assignment is rejected.
    @discardableResult
    func assign(subjectId: String, destination: Int) -> Bool {
        guard case .assigning = phase else { return false }
        do {
            state = try ClassificationEngine.assign(state, subjectId: subjectId,
                                                    destination: destination)
            lastError = nil
            if state.status == .complete {
                phase = .finished(ClassificationScorer.score(state))
            }
            return true
        } catch let e as ClassificationError {
            lastError = e
            return false
        } catch {
            lastError = nil
            return false
        }
    }

    func clearError() { lastError = nil }
}
