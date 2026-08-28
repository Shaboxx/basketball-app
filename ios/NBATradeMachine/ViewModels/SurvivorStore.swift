import Foundation
import SwiftUI
import Combine

/// Drives one SURVIVOR session. Created per-session by the launching view.
@MainActor
final class SurvivorStore: ObservableObject {

    enum Phase: Equatable {
        case playing
        case finished(Int)   // final streak
    }

    @Published private(set) var state: SurvivorState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: SurvivorError?

    init(state: SurvivorState) {
        self.state = state
        self.phase = state.status == .playing ? .playing : .finished(state.streak)
    }

    // See GameSetupStore: default-MainActor deinit trips a double-free under XCTest.
    nonisolated deinit {}

    func submit(subjectId: String) {
        guard case .playing = phase else { return }
        do {
            state = try SurvivorEngine.submitAnswer(state, subjectId: subjectId)
            lastError = nil
            if state.status != .playing { phase = .finished(state.streak) }
        } catch let e as SurvivorError {
            lastError = e
        } catch {
            lastError = nil
        }
    }

    func skip() {
        guard case .playing = phase else { return }
        do {
            state = try SurvivorEngine.skip(state)
            lastError = nil
            if state.status != .playing { phase = .finished(state.streak) }
        } catch let e as SurvivorError {
            lastError = e
        } catch {
            lastError = nil
        }
    }

    func clearError() { lastError = nil }
}
