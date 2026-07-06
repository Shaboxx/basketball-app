import Foundation
import Combine

/// Local (UserDefaults-backed) store of league trade proposals. Mirrors the
/// sibling stores (injectable defaults, JSON array, persist-per-mutation); every
/// state transition routes through `FantasyTradeEngine`. Execution is the one
/// cross-store action: it re-validates against CURRENT rosters and applies the
/// swap through `FantasyTeamStore` before stamping the trade executed.
@MainActor
final class FantasyTradeStore: ObservableObject {
    private static let tradesKey = "fantasyTrades"
    private let defaults: UserDefaults

    @Published private(set) var trades: [FantasyTrade] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.tradesKey),
           let decoded = try? JSONDecoder().decode([FantasyTrade].self, from: data) {
            self.trades = decoded
        }
    }

    // MARK: Reads
    /// A league's trades, most-recent first (append order reversed).
    func trades(for leagueId: UUID) -> [FantasyTrade] {
        trades.filter { $0.leagueId == leagueId }.reversed()
    }
    func trade(_ id: UUID) -> FantasyTrade? { trades.first { $0.id == id } }

    // MARK: Propose
    /// Create a proposed trade. The caller validates structure/rosters first (via
    /// FantasyTradeEngine); this stores what it's given.
    @discardableResult
    func propose(leagueId: UUID, fromTeamId: UUID, toTeamId: UUID,
                 fromSlugs: [String], toSlugs: [String], note: String = "") -> FantasyTrade {
        let trade = FantasyTrade(
            leagueId: leagueId, fromTeamId: fromTeamId, toTeamId: toTeamId,
            fromSlugs: fromSlugs.map(FantasyValueStore.canonicalSlug),
            toSlugs: toSlugs.map(FantasyValueStore.canonicalSlug),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        trades.append(trade)
        persist()
        return trade
    }

    // MARK: Non-executing transitions
    func accept(_ id: UUID) { apply(id, FantasyTradeEngine.accepting) }
    func reject(_ id: UUID) { apply(id, FantasyTradeEngine.rejecting) }
    func cancel(_ id: UUID) { apply(id, FantasyTradeEngine.cancelling) }
    func veto(_ id: UUID)   { apply(id, FantasyTradeEngine.vetoing) }
    /// Close a proposal because the recipient sent back a counter (a new proposal).
    func markCountered(_ id: UUID) { apply(id, FantasyTradeEngine.countering) }

    private func apply(_ id: UUID, _ transition: (FantasyTrade) -> FantasyTrade?) {
        guard let i = index(of: id), let next = transition(trades[i]) else { return }
        trades[i] = next
        persist()
    }

    // MARK: Execute (cross-store)
    enum ExecuteError: Equatable { case notFound, notAccepted, invalidNow }

    /// Re-validate the ACCEPTED trade against current rosters and, if still legal,
    /// swap the players (slot-preserving) and stamp it executed. Returns nil on
    /// success, or the reason it couldn't run (e.g. a player already moved).
    @discardableResult
    func execute(_ id: UUID, teamStore: FantasyTeamStore) -> ExecuteError? {
        guard let i = index(of: id) else { return .notFound }
        let t = trades[i]
        guard t.status == .accepted else { return .notAccepted }
        guard let from = teamStore.team(t.fromTeamId),
              let to = teamStore.team(t.toTeamId),
              FantasyTradeEngine.isValid(
                fromTeamId: t.fromTeamId, toTeamId: t.toTeamId,
                fromSlugs: t.fromSlugs, toSlugs: t.toSlugs,
                fromRoster: from.playerSlugs, toRoster: to.playerSlugs)
        else { return .invalidNow }

        teamStore.applyTrade(teamA: t.fromTeamId, sendsA: t.fromSlugs,
                             teamB: t.toTeamId, sendsB: t.toSlugs)
        guard let next = FantasyTradeEngine.executing(t) else { return .invalidNow }
        trades[i] = next
        persist()
        return nil
    }

    // MARK: Cleanup
    /// Drop every trade for a deleted league (called from the league-delete paths).
    func removeTrades(for leagueId: UUID) {
        trades.removeAll { $0.leagueId == leagueId }
        persist()
    }

    /// Drop every trade a deleted TEAM is on either side of (called from the
    /// team-delete paths) so no proposal dangles on a team that no longer exists.
    func removeTrades(involving teamId: UUID) {
        trades.removeAll { $0.fromTeamId == teamId || $0.toTeamId == teamId }
        persist()
    }

    private func index(of id: UUID) -> Int? { trades.firstIndex { $0.id == id } }

    private func persist() {
        if let data = try? JSONEncoder().encode(trades) {
            defaults.set(data, forKey: Self.tradesKey)
        }
    }
}
