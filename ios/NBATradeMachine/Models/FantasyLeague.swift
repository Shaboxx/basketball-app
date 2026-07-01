import Foundation

/// A locally-saved fantasy league: a named, ordered subset of saved `FantasyTeam` ids.
/// Persisted (JSON) by `FantasyLeagueStore`; never written to Firestore. `nonisolated`
/// + Codable so encode/decode + equality run off the MainActor and in plain XCTestCases.
/// It stores ONLY team ids — the round-robin schedule is generated deterministically
/// from `teamIds` (never stored) and the scoring format is the app's ACTIVE format
/// (never stored per-league), so the league can never drift out of sync.
nonisolated struct FantasyLeague: Codable, Identifiable, Hashable {
    /// Stable identity — survives rename/reorder.
    let id: UUID
    var name: String
    /// Ordered `FantasyTeam.id`s. A member team deleted from `FantasyTeamStore` leaves a
    /// dangling id here; it is skipped gracefully at render time (see §5.4 / §9), not pruned.
    /// Deduped on decode + by the store so the detail view's productions map (keyed by id)
    /// can never collide.
    var teamIds: [UUID]

    init(id: UUID = UUID(), name: String, teamIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.teamIds = teamIds
    }

    /// Forgiving decode: an older/partial local blob (missing `name`/`teamIds`) decodes
    /// safely, and any duplicate ids from a hand-edited/legacy blob are collapsed
    /// (first-wins, order-preserving) so downstream id-keyed maps stay unique.
    enum CodingKeys: String, CodingKey { case id, name, teamIds }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "League"
        let raw = try c.decodeIfPresent([UUID].self, forKey: .teamIds) ?? []
        var seen = Set<UUID>()
        teamIds = raw.filter { seen.insert($0).inserted }
    }
}
