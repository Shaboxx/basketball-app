import Foundation
import SwiftUI
import Combine

/// Local (UserDefaults-backed) store of the user's saved fantasy teams. CRUD +
/// a single "My Team" pointer. Mirrors `AppSettings`'s injectable-defaults seam
/// (`init(defaults:)`), but the payload is a JSON-encoded `[FantasyTeam]`.
/// No Firestore, no network. All roster edits route THROUGH these methods (the
/// builder holds only a `teamId`, never a mutable `FantasyTeam` copy) so the
/// published array stays the single source of truth.
@MainActor
final class FantasyTeamStore: ObservableObject {
    private static let teamsKey = "fantasyTeams"
    private static let myTeamKey = "fantasyMyTeamId"
    private let defaults: UserDefaults

    /// All saved teams, in creation order. `private(set)` — mutate only via CRUD.
    @Published private(set) var teams: [FantasyTeam] = []
    /// The one team flagged "My Team" (nil only when there are zero teams).
    @Published private(set) var myTeamId: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.teamsKey),
           let decoded = try? JSONDecoder().decode([FantasyTeam].self, from: data) {
            self.teams = decoded
        }
        if let raw = defaults.string(forKey: Self.myTeamKey) {
            self.myTeamId = UUID(uuidString: raw)
        }
        // Repair a dangling/absent pointer: default My Team to the first saved team.
        if myTeamId == nil || !teams.contains(where: { $0.id == myTeamId }) {
            myTeamId = teams.first?.id
        }
    }

    // MARK: Derived
    var myTeam: FantasyTeam? { teams.first { $0.id == myTeamId } }
    func team(_ id: UUID) -> FantasyTeam? { teams.first { $0.id == id } }

    // MARK: CRUD — teams
    @discardableResult
    func createTeam(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = FantasyTeam(name: trimmed.isEmpty ? "My Team" : trimmed)
        teams.append(team)
        if myTeamId == nil { myTeamId = team.id }   // first team auto-becomes My Team
        persist()
        return team.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = index(of: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        teams[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        teams.removeAll { $0.id == id }
        if myTeamId == id { myTeamId = teams.first?.id }   // reassign or clear
        persist()
    }

    func setMyTeam(_ id: UUID) {
        guard teams.contains(where: { $0.id == id }) else { return }
        myTeamId = id
        persist()
    }

    // MARK: CRUD — roster
    /// Append (deduped by canonical slug), preserving order.
    func addPlayer(_ slug: String, to id: UUID) {
        guard let i = index(of: id) else { return }
        let canon = FantasyValueStore.canonicalSlug(slug)
        guard !teams[i].playerSlugs.contains(where: { FantasyValueStore.canonicalSlug($0) == canon }) else { return }
        teams[i].playerSlugs.append(canon)
        persist()
    }

    func removePlayer(_ slug: String, from id: UUID) {
        guard let i = index(of: id) else { return }
        let canon = FantasyValueStore.canonicalSlug(slug)
        teams[i].playerSlugs.removeAll { FantasyValueStore.canonicalSlug($0) == canon }
        teams[i].slots[canon] = nil          // a departed player's slot choice goes with him
        persist()
    }

    /// Replace the whole roster (draft apply): slugs canonicalized + deduped,
    /// slot choices cleared so auto-fill re-derives the standard divide for the
    /// new roster.
    func setRoster(_ slugs: [String], for id: UUID) {
        guard let i = index(of: id) else { return }
        var seen = Set<String>()
        teams[i].playerSlugs = slugs.map(FantasyValueStore.canonicalSlug)
            .filter { seen.insert($0).inserted }
        teams[i].slots = [:]
        persist()
    }

    /// Set the team owner's display name (profanity-gated by callers via
    /// FantasyNameRules; the store trims but stays permissive on content).
    func setOwner(_ owner: String, for id: UUID) {
        guard let i = index(of: id) else { return }
        teams[i].ownerName = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Point the team at a stored logo file (see FantasyLogoStore).
    func setLogo(_ fileName: String?, for id: UUID) {
        guard let i = index(of: id) else { return }
        teams[i].logoFileName = fileName
        persist()
    }

    /// Record the user's slot choice for one rostered player. Limit enforcement is
    /// the caller's job (the detail view disables full targets); the resolved view
    /// of slots always goes through `FantasyRosterSlots.effectiveAssignments`.
    func setSlot(_ slug: String, in id: UUID, to slot: FantasySlot) {
        guard let i = index(of: id) else { return }
        let canon = FantasyValueStore.canonicalSlug(slug)
        guard teams[i].playerSlugs.contains(where: { FantasyValueStore.canonicalSlug($0) == canon }) else { return }
        teams[i].slots[canon] = slot
        persist()
    }

    /// Reorder support for the builder's `.onMove`.
    func movePlayer(in id: UUID, from source: IndexSet, to destination: Int) {
        guard let i = index(of: id) else { return }
        teams[i].playerSlugs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: Persistence
    private func index(of id: UUID) -> Int? { teams.firstIndex { $0.id == id } }

    private func persist() {
        if let data = try? JSONEncoder().encode(teams) {
            defaults.set(data, forKey: Self.teamsKey)
        }
        defaults.set(myTeamId?.uuidString, forKey: Self.myTeamKey)
    }
}
