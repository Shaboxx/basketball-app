import Foundation
import SwiftUI
import Combine

/// Local (UserDefaults-backed) store of the user's saved fantasy leagues. CRUD +
/// member-team add/remove/reorder. Mirrors `FantasyTeamStore` EXACTLY (injectable
/// `init(defaults:)` seam, a JSON-encoded array, explicit `persist()` per mutation),
/// but the payload is `[FantasyLeague]` and there is NO "my league" pointer.
/// No Firestore, no network. All edits route THROUGH these methods (a builder holds
/// only a `leagueId`, never a mutable `FantasyLeague` copy) so the published array
/// stays the single source of truth.
@MainActor
final class FantasyLeagueStore: ObservableObject {
    private static let leaguesKey = "fantasyLeagues"
    private let defaults: UserDefaults

    /// All saved leagues, in creation order. `private(set)` — mutate only via CRUD.
    @Published private(set) var leagues: [FantasyLeague] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.leaguesKey),
           let decoded = try? JSONDecoder().decode([FantasyLeague].self, from: data) {
            self.leagues = decoded
        }
    }

    // MARK: Derived
    func league(_ id: UUID) -> FantasyLeague? { leagues.first { $0.id == id } }

    // MARK: CRUD — leagues
    @discardableResult
    func createLeague(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let league = FantasyLeague(name: trimmed.isEmpty ? "New League" : trimmed)
        leagues.append(league)
        persist()
        return league.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = index(of: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        leagues[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        leagues.removeAll { $0.id == id }
        persist()
    }

    // MARK: CRUD — member teams
    /// Append a member team (deduped), preserving order.
    func addTeam(_ teamId: UUID, to id: UUID) {
        guard let i = index(of: id) else { return }
        guard !leagues[i].teamIds.contains(teamId) else { return }
        leagues[i].teamIds.append(teamId)
        persist()
    }

    func removeTeam(_ teamId: UUID, from id: UUID) {
        guard let i = index(of: id) else { return }
        leagues[i].teamIds.removeAll { $0 == teamId }
        persist()
    }

    /// Reorder support for the builder's `.onMove` (schedule regenerates from the new order).
    func moveTeam(in id: UUID, from source: IndexSet, to destination: Int) {
        guard let i = index(of: id) else { return }
        leagues[i].teamIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: League setup (rules + stakes)
    func setRules(_ rules: FantasyLeagueRules, in id: UUID) {
        guard let i = index(of: id) else { return }
        leagues[i].rules = rules
        persist()
    }

    func setStakes(_ stakes: FantasyLeagueStakes, in id: UUID) {
        guard let i = index(of: id) else { return }
        leagues[i].stakes = stakes
        persist()
    }

    // MARK: Persistence
    private func index(of id: UUID) -> Int? { leagues.firstIndex { $0.id == id } }

    private func persist() {
        if let data = try? JSONEncoder().encode(leagues) {
            defaults.set(data, forKey: Self.leaguesKey)
        }
    }
}
