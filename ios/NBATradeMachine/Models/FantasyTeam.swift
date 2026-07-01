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

    init(id: UUID = UUID(), name: String, playerSlugs: [String] = []) {
        self.id = id
        self.name = name
        self.playerSlugs = playerSlugs
    }

    /// Forgiving decode: a doc missing `name`/`playerSlugs` (older local blob) decodes safely.
    enum CodingKeys: String, CodingKey { case id, name, playerSlugs }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Team"
        playerSlugs = try c.decodeIfPresent([String].self, forKey: .playerSlugs) ?? []
    }
}
