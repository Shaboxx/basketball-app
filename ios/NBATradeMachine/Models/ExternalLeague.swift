import Foundation

/// Host-agnostic DTOs for importing an external fantasy league. Each connector
/// (ESPN/Yahoo/Sleeper/Fantrax) fetches its own JSON and maps it to ONE normalized
/// `ExternalLeagueSnapshot`, so the resolver + importer downstream never care which
/// platform the data came from. Pure value types, `nonisolated` so they decode +
/// compare off the MainActor and in plain XCTestCases.

/// Points to one external league. Persisted on `FantasyLeague` so a re-sync can find
/// and OVERWRITE the same local league instead of duplicating it.
nonisolated struct ExternalLeagueRef: Codable, Equatable, Hashable {
    let host: FantasyLeagueHost
    let leagueId: String
    /// Platform season key (e.g. "2025"); nil = the connector's current season.
    var season: String?

    init(host: FantasyLeagueHost, leagueId: String, season: String? = nil) {
        self.host = host
        self.leagueId = leagueId
        self.season = season
    }
}

/// A platform's scoring model, normalized to what `FantasyLeagueRules` can express.
nonisolated struct ExternalScoring: Equatable, Hashable {
    enum Kind: String, Equatable, Hashable { case categories, points, roto, unknown }
    var kind: Kind
    /// categories only: 8-cat (drops turnovers) vs 9-cat.
    var eightCat: Bool
    /// points only: Yahoo preset vs ESPN preset.
    var isYahoo: Bool

    init(kind: Kind, eightCat: Bool = false, isYahoo: Bool = false) {
        self.kind = kind
        self.eightCat = eightCat
        self.isYahoo = isYahoo
    }

    /// The app scoring preset this maps to, or nil (unknown → follow app default).
    var fantasyFormat: FantasyFormat? {
        switch kind {
        case .points:     return isYahoo ? .pointsYahoo : .pointsEspn
        case .roto:       return .roto
        case .categories: return eightCat ? .eightCat : .nineCat
        case .unknown:    return nil
        }
    }
}

/// One external player as a connector returns it, BEFORE identity resolution. The
/// optional NBA hints help the resolver; `name` is always present (every platform
/// returns a display name).
nonisolated struct ExternalPlayer: Equatable, Hashable, Identifiable {
    /// Platform-scoped id (kept so the resolution map keys back to this exact player).
    let externalId: String
    let name: String
    var nbaTricode: String?
    var nbaId: String?

    var id: String { externalId }

    init(externalId: String, name: String, nbaTricode: String? = nil, nbaId: String? = nil) {
        self.externalId = externalId
        self.name = name
        self.nbaTricode = nbaTricode
        self.nbaId = nbaId
    }
}

/// One external team + its (unresolved) roster.
nonisolated struct ExternalTeam: Equatable, Hashable, Identifiable {
    let externalId: String
    var name: String
    var ownerName: String
    /// Platform's stable OWNER id (Sleeper owner_id, ESPN/Yahoo user guid) when available —
    /// the correct key for deduping managers (two real people can share a display name, and
    /// one person's name can be spelled differently). nil → fall back to the owner name.
    var ownerId: String?
    var players: [ExternalPlayer]

    var id: String { externalId }

    init(externalId: String, name: String, ownerName: String = "",
         ownerId: String? = nil, players: [ExternalPlayer] = []) {
        self.externalId = externalId
        self.name = name
        self.ownerName = ownerName
        self.ownerId = ownerId
        self.players = players
    }
}

/// A lightweight league listing for the "pick which of my leagues to import" step
/// (Sleeper username → leagues; Yahoo token → leagues). `ref` re-fetches the full league.
nonisolated struct ExternalLeagueSummary: Equatable, Hashable, Identifiable {
    let ref: ExternalLeagueRef
    let name: String
    var id: String { "\(ref.host.rawValue):\(ref.leagueId):\(ref.season ?? "")" }
}

/// The normalized result of fetching an external league — everything the importer
/// needs. Managers/commissioner are derived from team owner names by the importer
/// (most platforms don't expose a distinct manager roster or the commissioner).
nonisolated struct ExternalLeagueSnapshot: Equatable {
    var name: String
    var scoring: ExternalScoring?
    var rosterLimits: FantasyRosterLimits?
    var teams: [ExternalTeam]

    init(name: String, scoring: ExternalScoring? = nil,
         rosterLimits: FantasyRosterLimits? = nil, teams: [ExternalTeam] = []) {
        self.name = name
        self.scoring = scoring
        self.rosterLimits = rosterLimits
        self.teams = teams
    }

    /// Every external player across all teams (for batch resolution).
    var allPlayers: [ExternalPlayer] { teams.flatMap(\.players) }
}
