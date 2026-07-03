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

    /// The first league (creation order) a team belongs to, or nil when the team
    /// is unaffiliated. The single "which league governs this team" convention,
    /// shared by roster-limit enforcement, standings, and the incomplete flag.
    func firstLeague(containing teamId: UUID) -> FantasyLeague? {
        leagues.first { $0.teamIds.contains(teamId) }
    }

    /// The roster limits ENFORCED for a team: its governing league's override when
    /// set, else the app-wide default. One source of truth so team-building, slot
    /// caps, grading, and the incomplete flag all agree.
    func effectiveLimits(for teamId: UUID, appWide: FantasyRosterLimits) -> FantasyRosterLimits {
        firstLeague(containing: teamId)?.rules.limits ?? appWide
    }

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
    /// Append a member team (deduped), preserving order. SINGLE-LEAGUE MEMBERSHIP:
    /// a team belongs to at most one league, so every enforcement site (roster
    /// limits, slots, grade, incomplete flag, draft) resolves the SAME governing
    /// league — no ambiguity. A team already in another league is refused here
    /// (the builder disables its row too).
    func addTeam(_ teamId: UUID, to id: UUID) {
        guard let i = index(of: id) else { return }
        guard !leagues[i].teamIds.contains(teamId) else { return }
        guard !leagues.contains(where: { $0.id != id && $0.teamIds.contains(teamId) }) else { return }
        leagues[i].teamIds.append(teamId)
        persist()
    }

    /// The OTHER league a team already belongs to (for the builder's disable +
    /// caption), or nil when it's free to join.
    func otherLeague(for teamId: UUID, excluding leagueId: UUID) -> FantasyLeague? {
        leagues.first { $0.id != leagueId && $0.teamIds.contains(teamId) }
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

    // MARK: League setup (rules + stakes + host)
    func setRules(_ rules: FantasyLeagueRules, in id: UUID) {
        guard let i = index(of: id) else { return }
        leagues[i].rules = rules
        persist()
    }

    func setHost(_ host: FantasyLeagueHost, in id: UUID) {
        guard let i = index(of: id) else { return }
        leagues[i].host = host
        persist()
    }

    // MARK: Managers (commissioner tools)
    /// Add a manager (caller validates name via FantasyNameRules). Returns the new id.
    @discardableResult
    func addManager(name: String, to leagueId: UUID) -> UUID? {
        guard let i = index(of: leagueId) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let m = FantasyManager(name: trimmed)
        leagues[i].managers.append(m)
        persist()
        return m.id
    }

    func renameManager(_ managerId: UUID, to name: String, in leagueId: UUID) {
        guard let i = index(of: leagueId),
              let m = leagues[i].managers.firstIndex(where: { $0.id == managerId }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        leagues[i].managers[m].name = trimmed
        persist()
    }

    /// Remove a manager: also clears the commissioner flag if it was them and drops
    /// every team assignment pointing at them (the team keeps its last ownerName).
    func removeManager(_ managerId: UUID, from leagueId: UUID) {
        guard let i = index(of: leagueId) else { return }
        leagues[i].managers.removeAll { $0.id == managerId }
        if leagues[i].commissionerId == managerId { leagues[i].commissionerId = nil }
        for (teamId, mid) in leagues[i].teamManager where mid == managerId {
            leagues[i].teamManager[teamId] = nil
        }
        persist()
    }

    /// Designate (or clear with nil) the commissioner. No-op if the manager isn't in the league.
    func setCommissioner(_ managerId: UUID?, in leagueId: UUID) {
        guard let i = index(of: leagueId) else { return }
        if let managerId, !leagues[i].managers.contains(where: { $0.id == managerId }) { return }
        leagues[i].commissionerId = managerId
        persist()
    }

    /// Assign a manager (or clear with nil) to a member team. Returns the manager's
    /// name to push onto the team's ownerName (the view owns the FantasyTeamStore).
    @discardableResult
    func assignManager(_ managerId: UUID?, toTeam teamId: UUID, in leagueId: UUID) -> String? {
        guard let i = index(of: leagueId) else { return nil }
        if let managerId, !leagues[i].managers.contains(where: { $0.id == managerId }) { return nil }
        leagues[i].teamManager[teamId] = managerId
        persist()
        return managerId.flatMap { mid in leagues[i].managers.first { $0.id == mid }?.name }
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
