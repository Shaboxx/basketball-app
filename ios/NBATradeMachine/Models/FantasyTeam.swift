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
    /// The human who runs this team (shown where the NBA grid shows the city).
    var ownerName: String
    /// File name of the user-picked logo inside `FantasyLogoStore`'s directory;
    /// nil → the default placeholder.
    var logoFileName: String?

    init(id: UUID = UUID(), name: String, playerSlugs: [String] = [],
         slots: [String: FantasySlot] = [:], ownerName: String = "",
         logoFileName: String? = nil) {
        self.id = id
        self.name = name
        self.playerSlugs = playerSlugs
        self.slots = slots
        self.ownerName = ownerName
        self.logoFileName = logoFileName
    }

    /// Forgiving decode: a doc missing any newer field (older local blob) decodes
    /// safely — pre-slots teams get an empty map (pure auto-fill), pre-logo teams
    /// the placeholder.
    enum CodingKeys: String, CodingKey { case id, name, playerSlugs, slots, ownerName, logoFileName }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Team"
        playerSlugs = try c.decodeIfPresent([String].self, forKey: .playerSlugs) ?? []
        slots = try c.decodeIfPresent([String: FantasySlot].self, forKey: .slots) ?? [:]
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
        logoFileName = try c.decodeIfPresent(String.self, forKey: .logoFileName)
    }

    /// Grid initials (the NBA-abbreviation slot): first letters of up to three
    /// words, uppercased — "Springfield Iso Joes" → "SIJ", "Warriors" → "W".
    var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(3)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

/// A team is INCOMPLETE (red flag on the Teams grid) when it has no league
/// affiliation or its roster is short of the lineup size — either gap means
/// it can't field a full scoring lineup in a real league week.
nonisolated enum FantasyTeamCompleteness {
    static func isIncomplete(playerCount: Int, inAnyLeague: Bool, lineupLimit: Int) -> Bool {
        !inAnyLeague || playerCount < lineupLimit
    }
}
