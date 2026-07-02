import Foundation

/// A locally-saved fantasy roster: a named, ordered list of player slugs.
/// Persisted (JSON) by `FantasyTeamStore`; never written to Firestore.
/// `nonisolated` + Codable so encode/decode + equality run off the MainActor
/// and in plain XCTestCases. There is NO per-team "isMyTeam" flag — the single
/// "My Team" designation lives in `FantasyTeamStore.myTeamId` (one source of truth).
nonisolated struct FantasyTeam: Codable, Identifiable, Hashable {
    /// Stable identity — survives rename/reorder and is the key `myTeamId` points at.
    let id: UUID
    var name: String
    /// Ordered roster of canonical player slugs (canonicalized on insert; see store `addPlayer`).
    var playerSlugs: [String]
    /// The user's explicit slot choices (canonical slug → slot). Sparse: players
    /// with no entry auto-fill via `FantasyRosterSlots.effectiveAssignments`.
    var slots: [String: FantasySlot]

    init(id: UUID = UUID(), name: String, playerSlugs: [String] = [],
         slots: [String: FantasySlot] = [:]) {
        self.id = id
        self.name = name
        self.playerSlugs = playerSlugs
        self.slots = slots
    }

    /// Forgiving decode: a doc missing `name`/`playerSlugs`/`slots` (older local
    /// blob) decodes safely — pre-slots teams get an empty map (pure auto-fill).
    enum CodingKeys: String, CodingKey { case id, name, playerSlugs, slots }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Team"
        playerSlugs = try c.decodeIfPresent([String].self, forKey: .playerSlugs) ?? []
        slots = try c.decodeIfPresent([String: FantasySlot].self, forKey: .slots) ?? [:]
    }
}
