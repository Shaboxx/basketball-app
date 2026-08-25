import Foundation
import SwiftUI
import Combine

/// Drives ONE local game session (solo, pass-and-play, CPU seats). Owns the
/// pure engine state, exposes intents, and schedules CPU turns. Created
/// per-session by the launching view (`@StateObject`), NOT injected app-wide.
@MainActor
final class GameSessionStore: ObservableObject {

    enum Phase: Equatable {
        case handoff(seat: Int)       // pass-the-device gate before a human turn
        case picking(seat: Int)
        case cpuThinking(seat: Int)
        case finished(GameResult)
    }

    @Published private(set) var state: RosterGameState
    @Published private(set) var phase: Phase
    @Published private(set) var lastError: GameEngineError?

    private let cpuDelay: Duration    // injectable so tests run CPUs instantly
    private var cpuTask: Task<Void, Never>?

    init(state: RosterGameState, cpuDelay: Duration = .seconds(1)) {
        self.state = state
        self.cpuDelay = cpuDelay
        self.phase = .picking(seat: 0)   // placeholder; advancePhase sets the truth
        advancePhase()
    }

    // Synthesized deinit would be MainActor-isolated → executor-hop double-free
    // under XCTest (see GameSetupStore). No isolated teardown needed.
    nonisolated deinit {}

    /// Seats from setup: humans first, then CPUs. A lone human is "You".
    nonisolated static func participants(humans: Int, cpus: Int) -> [GameParticipant] {
        let h = (0..<max(humans, 0)).map {
            GameParticipant(id: $0, kind: .human,
                            displayName: humans > 1 ? "Player \($0 + 1)" : "You")
        }
        let c = (0..<max(cpus, 0)).map {
            GameParticipant(id: max(humans, 0) + $0, kind: .cpu,
                            displayName: "CPU \($0 + 1)")
        }
        return h + c
    }

    // MARK: - Intents

    func confirmHandoff() {
        if case .handoff(let seat) = phase { phase = .picking(seat: seat) }
    }

    func pick(entityId: String, slotId: String) {
        guard case .picking(let seat) = phase else { return }
        do {
            state = try RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: entityId, slotId: slotId)
            lastError = nil
            advancePhase()
        } catch let error as GameEngineError {
            lastError = error
        } catch {
            lastError = nil
        }
    }

    func clearError() { lastError = nil }

    // MARK: - Phase machine

    private var isPassAndPlay: Bool {
        state.participants.filter { $0.kind == .human }.count > 1
    }

    private func advancePhase() {
        guard state.status == .active,
              let seat = RosterConstructionEngine.currentSeat(state) else {
            cpuTask?.cancel()   // make "no CPU work after the game ends" explicit
            phase = .finished(RosterConstructionEngine.buildResult(state))
            return
        }
        if state.participants[seat].kind == .cpu {
            phase = .cpuThinking(seat: seat)
            scheduleCPU(seat: seat)
        } else if isPassAndPlay {
            phase = .handoff(seat: seat)
        } else {
            phase = .picking(seat: seat)
        }
    }

    private func scheduleCPU(seat: Int) {
        cpuTask?.cancel()
        cpuTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.cpuDelay)
            guard !Task.isCancelled else { return }
            self.applyCPUPick(seat: seat)
        }
    }

    private func applyCPUPick(seat: Int) {
        guard case .cpuThinking(let expected) = phase, expected == seat else { return }
        var rng = state.rng
        guard let pick = GameCPUPolicy.choosePick(state, seat: seat, rng: &rng),
              var next = try? RosterConstructionEngine.submitPick(
                state, seat: seat, entityId: pick.entityId, slotId: pick.slotId)
        else {
            // No legal pick (constraint corner) — finish honestly, don't hang.
            var stuck = state
            stuck.status = .complete
            state = stuck
            advancePhase()
            return
        }
        // The policy consumed RNG values submitPick didn't see; keep the stream
        // consistent so replays with the same seed stay identical.
        if next.definition.selection.method != .randomOffer { next.rng = rng }
        state = next
        advancePhase()
    }
}
