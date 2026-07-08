import Foundation
import Combine

@MainActor
final class TeamsViewModel: ObservableObject {
    @Published var teams: [Team] = []
    @Published var playersByTeamId: [String: [Player]] = [:]   // each roster pre-sorted salary desc
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Bumped on each successful load — a cheap signal other tabs can observe to
    /// re-derive from the shared player set without diffing the whole dictionary.
    @Published private(set) var dataVersion = 0

    /// slug -> Player index for O(1) cross-tab lookup (rebuilt on each load).
    private var playerBySlug: [String: Player] = [:]

    /// League-wide per-layer depth statistics, computed once per data load. The
    /// build is O(teams × roster × positions) and the depth-chart sheets call it
    /// on EVERY render (team page + post-trade sheet), so cache it and invalidate
    /// only when `dataVersion` advances. The result depends solely on the league
    /// rosters (`playersByTeamId`), which change only on `reload()`.
    private var _leagueLayerStats: TeamDepthChartBuilder.LeagueLayerStats?
    private var _leagueLayerStatsVersion = -1
    var leagueLayerStats: TeamDepthChartBuilder.LeagueLayerStats {
        if _leagueLayerStats == nil || _leagueLayerStatsVersion != dataVersion {
            _leagueLayerStats = TeamDepthChartBuilder.leagueLayerStats(rostersByTeam: playersByTeamId)
            _leagueLayerStatsVersion = dataVersion
        }
        return _leagueLayerStats!
    }

    /// Every rostered player, flattened — the Players tab derives from this instead of
    /// issuing a SECOND whole-collection fetch. Cached (the flatMap was re-run on every access,
    /// and several fantasy views hit it per row) and invalidated on `dataVersion`.
    private var _allRostered: [Player]?
    private var _allRosteredVersion = -1
    var allRosteredPlayers: [Player] {
        if _allRostered == nil || _allRosteredVersion != dataVersion {
            _allRostered = playersByTeamId.values.flatMap { $0 }
            _allRosteredVersion = dataVersion
        }
        return _allRostered!
    }

    /// Canonical-slug → Player, cached. The fantasy roster/trade/draft views subscript this per
    /// row; building it per access (a `Dictionary` over ~500 players, each through the regex-based
    /// `canonicalSlug`) was a per-render hotspot. Invalidated on `dataVersion`.
    private var _playerByCanonical: [String: Player]?
    private var _playerByCanonicalVersion = -1
    var playerByCanonicalSlug: [String: Player] {
        if _playerByCanonical == nil || _playerByCanonicalVersion != dataVersion {
            _playerByCanonical = Dictionary(allRosteredPlayers.map { (FantasyValueStore.canonicalSlug($0.slug), $0) },
                                            uniquingKeysWith: { a, _ in a })
            _playerByCanonicalVersion = dataVersion
        }
        return _playerByCanonical!
    }

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard teams.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        // Stale-while-revalidate: paint the on-disk cache INSTANTLY (skip a cache miss), then
        // overwrite from the SERVER. On a flaky network the cache shows immediately instead of
        // blocking on a slow server round-trip; ContentView's ConnectivityMonitor re-runs this
        // on reconnect so the fresh server value still lands.
        if let cached = try? await fetchRosters(source: .cache), !cached.players.isEmpty {
            apply(cached)
        }
        do {
            apply(try await fetchRosters(source: .server))
            errorMessage = nil
        } catch {
            // Keep whatever we already painted (cache); only surface an error with nothing to show.
            if teams.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func fetchRosters(source: FetchSource) async throws -> (teams: [Team], players: [Player]) {
        async let teamsTask = service.fetchTeams(source: source)
        async let playersTask = service.fetchPlayers(source: source)
        return try await (teams: teamsTask, players: playersTask)
    }

    private func apply(_ rosters: (teams: [Team], players: [Player])) {
        self.teams = rosters.teams.sorted { $0.fullName < $1.fullName }
        // Sort each roster ONCE here (salary desc) so players(for:) is an O(1) lookup
        // — it funnels all trade/cap/sort/depth math and was re-sorting on every call.
        self.playersByTeamId = Dictionary(grouping: rosters.players, by: { $0.teamId })
            .mapValues { $0.sorted { $0.currentSalary > $1.currentSalary } }
        self.playerBySlug = Dictionary(rosters.players.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        self.dataVersion += 1
    }

    func players(for teamId: String) -> [Player] {
        playersByTeamId[teamId] ?? []   // pre-sorted (salary desc) at load
    }

    func totalSalary(for teamId: String) -> Int {
        players(for: teamId).reduce(0) { $0 + $1.currentSalary }
    }

    /// Resolve a player across all rosters by canonical slug — for cross-tab
    /// navigation (e.g. the News tab's Hot Players strip). Nil if not on a roster.
    /// O(1) via the slug index (was an O(all-players) scan per call).
    func player(slug: String) -> Player? { playerBySlug[slug] }

    /// Flat list of every player across every roster. Used for league-wide
    /// percentile math (value-gap on the profile). Not memoized — the source
    /// dictionary only changes on `load()` so the cost of recomputing per
    /// caller is negligible against the cost of plumbing invalidation.
    private var allPlayers: [Player] {
        playersByTeamId.values.flatMap { $0 }
    }

    /// League-relative ranks for a player's salary and Rev-2 total σ, plus
    /// the gap in percentile points. Returns nil unless both signals exist:
    /// one alone has no "gap" to report. Percentiles are 0–100, higher =
    /// "more". A positive `gap` means the player is paid like a higher-tier
    /// asset than they play (overvalued); negative means underpaid for the
    /// rating they earn.
    func valueGap(for player: Player) -> (salaryPct: Int, sigmaPct: Int, gap: Int)? {
        let players = allPlayers
        guard !players.isEmpty else { return nil }

        let salary = player.currentSalary
        let salaries = players.map(\.currentSalary).filter { $0 > 0 }
        guard !salaries.isEmpty, salary > 0 else { return nil }

        guard let sigma = player.dispTotal else { return nil }
        let sigmas = players.compactMap { $0.dispTotal }
        guard sigmas.count >= 10 else { return nil }   // too few rated to rank

        let salaryPct = Self.percentile(of: Double(salary), in: salaries.map(Double.init))
        let sigmaPct = Self.percentile(of: sigma, in: sigmas)
        return (salaryPct, sigmaPct, salaryPct - sigmaPct)
    }

    /// Standard "rank percentile" — share of the population strictly below
    /// the target, expressed as an int 0–100. Ties count as half-credit so
    /// duplicates don't pile up at a single integer.
    private static func percentile(of value: Double, in population: [Double]) -> Int {
        let n = Double(population.count)
        guard n > 0 else { return 0 }
        var below = 0.0
        for v in population {
            if v < value { below += 1 }
            else if v == value { below += 0.5 }
        }
        return Int((below / n * 100).rounded())
    }

    /// Sum of OFF/DEF display value across the rated roster, plus how many
    /// players of the roster carry a display value. Returns (0,0,0,total) when
    /// no roster player is rated yet — callers must treat `rated == 0` as "hide
    /// the summary," not as "team is exactly average."
    func latentValueRollup(for teamId: String) -> (off: Double, def: Double, rated: Int, total: Int) {
        let roster = players(for: teamId)
        var off = 0.0
        var def = 0.0
        var rated = 0
        for p in roster {
            let o = p.dispOff
            let d = p.dispDef
            guard o != nil || d != nil else { continue }
            off += o ?? 0
            def += d ?? 0
            rated += 1
        }
        return (off, def, rated, roster.count)
    }
}
