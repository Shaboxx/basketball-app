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
    /// ESPN/Yahoo-style league setup overrides (scoring/custom categories/roster
    /// shape/playoffs). Defaults to "follow the app settings".
    var rules: FantasyLeagueRules
    /// Entry stakes (recorded only — payment happens on the linked platform).
    var stakes: FantasyLeagueStakes
    /// Where the real league lives (This App / ESPN / Yahoo / Fantrax / Other).
    var host: FantasyLeagueHost
    /// Scoring model — standard, or Dream Team (any player, shared stats split by
    /// ownership count). Defaults to standard on legacy leagues.
    var mode: FantasyLeagueMode
    /// The people in the league (commissioner-managed). Empty on legacy leagues.
    var managers: [FantasyManager]
    /// Which manager is the commissioner (nil = unset). Cleared if that manager is removed.
    var commissionerId: UUID?
    /// Primary manager per member team (teamId → managerId). Assigning also pushes
    /// the manager's name onto the team's `ownerName` (done in the store).
    var teamManager: [UUID: UUID]

    init(id: UUID = UUID(), name: String, teamIds: [UUID] = [],
         rules: FantasyLeagueRules = .none, stakes: FantasyLeagueStakes = .none,
         host: FantasyLeagueHost = .thisApp, mode: FantasyLeagueMode = .standard,
         managers: [FantasyManager] = [],
         commissionerId: UUID? = nil, teamManager: [UUID: UUID] = [:]) {
        self.id = id
        self.name = name
        self.teamIds = teamIds
        self.rules = rules
        self.stakes = stakes
        self.host = host
        self.mode = mode
        self.managers = managers
        self.commissionerId = commissionerId
        self.teamManager = teamManager
    }

    func manager(_ id: UUID?) -> FantasyManager? { id.flatMap { mid in managers.first { $0.id == mid } } }

    /// Forgiving decode: an older/partial local blob (missing `name`/`teamIds`/
    /// `rules`/`stakes`) decodes safely, and any duplicate ids from a hand-edited/
    /// legacy blob are collapsed (first-wins, order-preserving) so downstream
    /// id-keyed maps stay unique.
    enum CodingKeys: String, CodingKey {
        case id, name, teamIds, rules, stakes, host, mode, managers, commissionerId, teamManager
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "League"
        let raw = try c.decodeIfPresent([UUID].self, forKey: .teamIds) ?? []
        var seen = Set<UUID>()
        teamIds = raw.filter { seen.insert($0).inserted }
        rules = try c.decodeIfPresent(FantasyLeagueRules.self, forKey: .rules) ?? .none
        stakes = try c.decodeIfPresent(FantasyLeagueStakes.self, forKey: .stakes) ?? .none
        host = try c.decodeIfPresent(FantasyLeagueHost.self, forKey: .host) ?? .thisApp
        mode = try c.decodeIfPresent(FantasyLeagueMode.self, forKey: .mode) ?? .standard
        managers = try c.decodeIfPresent([FantasyManager].self, forKey: .managers) ?? []
        commissionerId = try c.decodeIfPresent(UUID.self, forKey: .commissionerId)
        teamManager = try c.decodeIfPresent([UUID: UUID].self, forKey: .teamManager) ?? [:]
    }
}
