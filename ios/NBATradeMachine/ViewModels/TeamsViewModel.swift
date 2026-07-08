import Foundation
import Combine

@MainActor
final class TeamsViewModel: ObservableObject {
    /// How the Teams grid is sorted (persisted by the view via @AppStorage).
    enum SortMode: String, CaseIterable, Identifiable {
        case name, totalSigmaDesc, offSigmaDesc, defSigmaDesc
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name:           return "Name"
            case .totalSigmaDesc: return "Overall"
            case .offSigmaDesc:   return "Offense"
            case .defSigmaDesc:   return "Defense"
            }
        }
    }

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

    // MARK: - 0-100 value grades (percentile) — memoized on dataVersion

    /// Which value channel a grade reflects, so the badge stays MONOTONIC with the active sort
    /// (sorting by Offense shows the offense grade, etc.).
    enum ValueChannel: Hashable {
        case total, off, def
        var label: String { switch self { case .total: "OVR"; case .off: "OFF"; case .def: "DEF" } }
    }

    private var _playerGrades: [ValueChannel: [String: Int]] = [:]
    private var _teamGrades: [ValueChannel: [String: Int]] = [:]
    private var _gradesVersion = -1

    /// A player's value as a 0-100 grade (percentile of `channel` among rated players) — a legible
    /// anchor for the raw σ. Nil until enough players are rated.
    func playerGrade(for player: Player, channel: ValueChannel = .total) -> Int? {
        rebuildGradesIfNeeded()
        return _playerGrades[channel]?[player.slug]
    }

    /// A team's value as a 0-100 grade (percentile of `channel` among rated teams).
    func teamGrade(for teamId: String, channel: ValueChannel = .total) -> Int? {
        rebuildGradesIfNeeded()
        return _teamGrades[channel]?[teamId]
    }

    /// Build every grade map ONCE per load — percentile is O(n) per entry, so a grade per row
    /// would be O(n²) on every render. Cached, keyed on dataVersion.
    private func rebuildGradesIfNeeded() {
        guard _gradesVersion != dataVersion else { return }
        _gradesVersion = dataVersion

        let players = allRosteredPlayers
        _playerGrades = [
            .total: Self.gradeMap(players, \.dispTotal),
            .off:   Self.gradeMap(players, \.dispOff),
            .def:   Self.gradeMap(players, \.dispDef),
        ]

        let rated = teams.compactMap { t -> (id: String, off: Double, def: Double)? in
            let r = latentValueRollup(for: t.teamId)
            return r.rated > 0 ? (t.teamId, r.off, r.def) : nil
        }
        _teamGrades = [
            .total: Self.teamGradeMap(rated) { $0.off + $0.def },
            .off:   Self.teamGradeMap(rated) { $0.off },
            .def:   Self.teamGradeMap(rated) { $0.def },
        ]
    }

    /// Percentile grade per player for one value channel (≥10 rated, else empty).
    private static func gradeMap(_ players: [Player], _ key: KeyPath<Player, Double?>) -> [String: Int] {
        let vals = players.compactMap { $0[keyPath: key] }
        guard vals.count >= 10 else { return [:] }
        var map: [String: Int] = [:]
        for p in players { if let v = p[keyPath: key] { map[p.slug] = percentile(of: v, in: vals) } }
        return map
    }

    /// Percentile grade per team for one value function (≥4 rated, else empty).
    private static func teamGradeMap(_ teams: [(id: String, off: Double, def: Double)],
                                     _ value: ((id: String, off: Double, def: Double)) -> Double) -> [String: Int] {
        guard teams.count >= 4 else { return [:] }
        let pop = teams.map(value)
        var map: [String: Int] = [:]
        for t in teams { map[t.id] = percentile(of: value(t), in: pop) }
        return map
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

    // MARK: - Sorted / filtered grid (memoized)

    // Recomputed only when (dataVersion, sort, query) changes — NOT on every render (mirrors
    // PlayersViewModel.filtered). Private + non-@Published so writing the cache from
    // displayedTeams(sort:query:) doesn't trigger objectWillChange.
    private var _displayed: [Team]?
    private var _displayedKey: String?

    /// Teams sorted by `sort` and search-filtered by `query`, memoized on (dataVersion, sort, query).
    func displayedTeams(sort: SortMode, query: String) -> [Team] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let key = "\(dataVersion)|\(sort.rawValue)|\(q)"
        if _displayedKey == key, let cached = _displayed { return cached }
        let sorted = sortedTeams(sort)
        let result = q.isEmpty ? sorted : sorted.filter {
            $0.fullName.lowercased().contains(q) || $0.city.lowercased().contains(q)
                || $0.name.lowercased().contains(q) || $0.tricode.lowercased().contains(q)
        }
        _displayed = result
        _displayedKey = key
        return result
    }

    private func sortedTeams(_ sort: SortMode) -> [Team] {
        let channel: SortChannel
        switch sort {
        case .name:           return teams.sorted { $0.fullName < $1.fullName }
        case .totalSigmaDesc: channel = .total
        case .offSigmaDesc:   channel = .off
        case .defSigmaDesc:   channel = .def
        }
        // Schwartzian: compute each team's sort key ONCE (sortKey loops the roster), then sort.
        return teams.map { ($0, sortKey($0, channel)) }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private enum SortChannel { case off, def, total }
    private func sortKey(_ team: Team, _ channel: SortChannel) -> Double {
        let r = latentValueRollup(for: team.teamId)
        guard r.rated > 0 else { return -Double.infinity }
        switch channel {
        case .off:   return r.off
        case .def:   return r.def
        case .total: return r.off + r.def
        }
    }
}
