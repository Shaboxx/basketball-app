import Foundation
import Combine

/// Local (UserDefaults-backed) store of league drafts — one per league, keyed by
/// `leagueId`. Mirrors the sibling stores (injectable defaults, JSON array,
/// persist-per-mutation); every transition routes through `FantasyDraftEngine`.
@MainActor
final class FantasyDraftStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    private static let draftsKey = "fantasyDrafts"
    private let defaults: UserDefaults

    @Published private(set) var drafts: [FantasyDraft] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.draftsKey),
           let decoded = try? JSONDecoder().decode([FantasyDraft].self, from: data) {
            self.drafts = decoded
        }
    }

    func draft(for leagueId: UUID) -> FantasyDraft? {
        drafts.first { $0.leagueId == leagueId }
    }

    /// Start (or restart) the league's draft. Replaces any existing draft.
    @discardableResult
    func startDraft(leagueId: UUID, order: [UUID], rounds: Int) -> FantasyDraft? {
        guard order.count >= 2, rounds >= 1 else { return nil }
        let draft = FantasyDraft(leagueId: leagueId, order: order, rounds: rounds)
        drafts.removeAll { $0.leagueId == leagueId }
        drafts.append(draft)
        persist()
        return draft
    }

    /// Returns nil on success, or the engine's rejection reason.
    @discardableResult
    func makePick(leagueId: UUID, slug: String) -> FantasyDraftEngine.PickError? {
        guard let i = index(of: leagueId) else { return .notInProgress }
        switch FantasyDraftEngine.makingPick(drafts[i], slug: slug) {
        case .success(let next):
            drafts[i] = next
            persist()
            return nil
        case .failure(let err):
            return err
        }
    }

    func undoLastPick(leagueId: UUID) {
        guard let i = index(of: leagueId) else { return }
        drafts[i] = FantasyDraftEngine.undoingLastPick(drafts[i])
        persist()
    }

    func resetDraft(leagueId: UUID) {
        drafts.removeAll { $0.leagueId == leagueId }
        persist()
    }

    /// Stamp a completed draft as applied (rosters written to the teams).
    func markApplied(leagueId: UUID) {
        guard let i = index(of: leagueId), drafts[i].status == .complete else { return }
        drafts[i].status = .applied
        persist()
    }

    private func index(of leagueId: UUID) -> Int? {
        drafts.firstIndex { $0.leagueId == leagueId }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: Self.draftsKey)
        }
    }
}
