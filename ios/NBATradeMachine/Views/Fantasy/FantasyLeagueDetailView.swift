import SwiftUI

/// One league's Standings + Schedule, switched by a segmented `Picker`. THIS is the view
/// that resolves productions via the seam on the MainActor and hands the pure
/// `[UUID: FantasyTeamProduction]` map to the `nonisolated` engine (schedule / standings /
/// matchup scoring). Reads the ACTIVE format each render (no per-league stored format),
/// skips dangling member ids (§9), shows the honest projected-mode banner, and — for `< 2`
/// member teams — a unified guard card for both segments. A tapped matchup opens
/// `FantasyMatchupDetailView` with the already-resolved productions (no re-resolution).
struct FantasyLeagueDetailView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var fantasyActualsStore: FantasyActualsStore
    @EnvironmentObject var playerGameLogsStore: PlayerGameLogsStore
    @EnvironmentObject var appSettings: AppSettings

    let leagueId: UUID

    enum Segment: String, CaseIterable, Identifiable {
        case standings = "Standings", schedule = "Schedule"
        var id: String { rawValue }
    }
    @SceneStorage("fantasyLeagueSegment") private var segment: Segment = .standings   // NAV-07
    @State private var selectedPairing: FantasyMatchupPairing?
    /// The 0-based schedule week index for the tapped matchup row (nil for non-weekly or
    /// when the sheet was opened without a specific week context).
    @State private var selectedPairingWeekIndex: Int?
    @State private var showLeagueSettings = false
    @State private var showDraftRoom = false
    @State private var showTrades = false
    @State private var showManagers = false
    @State private var showSchedule = false
    @State private var confirmResetDraft = false
    @EnvironmentObject var fantasyDraftStore: FantasyDraftStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @EnvironmentObject var teamsVM: TeamsViewModel

    // MARK: Derived (recomputed each render — cheap; the engine is pure)
    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }

    // MARK: Weekly mode gate
    /// Weekly H2H scoring is active when ALL four conditions are met (spec §UI):
    ///   1. User has selected Live stat source.
    ///   2. The fantasy calendar is configured (regularStart + playoffsStart known).
    ///   3. The scoring format is H2H category or H2H points (NOT roto).
    ///   4. The league is in standard mode (not Dream Team).
    /// When false, all existing projected/live-season-to-date behavior is unchanged.
    private var isWeeklyMode: Bool {
        guard appSettings.statSource == .live else { return false }
        guard appSettings.fantasyCalendar.isConfigured else { return false }
        guard !isDreamTeam else { return false }
        // Roto stays season-cumulative (spec §4); custom categories are H2H, points are H2H.
        guard format != .roto else { return false }
        return true
    }

    /// This league's scoring: its own rules when set, else the app-wide format.
    private var format: FantasyFormat {
        league?.rules.effectiveFormat(appDefault: appSettings.fantasyFormat)
            ?? appSettings.fantasyFormat
    }
    /// Custom category mask (custom leagues score H2H over exactly these).
    private var customCats: [FantasyLeagueCategory]? { league?.rules.effectiveCustomCategories }
    /// Points-scoring only when the format is a points preset AND no custom mask.
    private var pointsScoring: Bool { format.isPoints && customCats == nil }

    /// Still-existing member teams, in league order (dangling ids skipped — §9).
    private var memberTeams: [FantasyTeam] {
        (fantasyLeagueStore.league(leagueId)?.teamIds ?? []).compactMap { fantasyTeamStore.team($0) }
    }
    private var teamIds: [UUID] { memberTeams.map(\.id) }

    /// The active source, chosen on the GLOBAL toggle. Both conform to `FantasyStatSource`
    /// and emit `FantasyTeamProduction`, so the engine below is untouched.
    private var source: FantasyStatSource {
        switch appSettings.statSource {
        case .projected:
            return ProjectedStatSource(values: fantasyStore.values)
        case .live:
            return ActualsStatSource(actuals: fantasyActualsStore.actualsBySlug,
                                     season: fantasyActualsStore.season)
        }
    }

    /// Dream Team mode: any team may roster any player and shared players' counting
    /// stats split by ownership count. Productions come from the ownership-division
    /// engine (raw scale) instead of the per-team source.
    private var isDreamTeam: Bool { league?.mode == .dreamTeam }

    // MARK: Weekly mode helpers

    /// All canonical player slugs rostered across every member team (de-duplicated).
    /// Used to determine which logs to request from `PlayerGameLogsStore`.
    private var allRosteredSlugs: [String] {
        Array(Set(memberTeams.flatMap(\.playerSlugs).map(FantasyValueStore.canonicalSlug)))
    }

    /// Local leagues always use alwaysCurrent eligibility (spec §6 local).
    /// `playerGameLogsStore.logsBySlug` is a snapshot of already-loaded docs.
    private var eligibility: RosterEligibility {
        let rosters = Dictionary(uniqueKeysWithValues: memberTeams.map {
            ($0.id, $0.playerSlugs)
        })
        return RosterEligibility.alwaysCurrent(rosters: rosters)
    }

    /// Precomputed `[weekIndex: [teamId: (FantasyTeamProduction, resolved)]]` for
    /// every schedule week, using `FantasyWeeklySeason.teamWeekProduction`. Only
    /// computed when `isWeeklyMode` is true (callers guard on that flag).
    private var weeklyProductionsByWeek: [Int: [UUID: (FantasyTeamProduction, Bool)]] {
        let logs = playerGameLogsStore.logsBySlug
        // Slugs whose Firestore fetch SUCCEEDED (incl. nil-doc "played zero games").
        // Spec §3: resolved = a successful fetch for ≥1 rostered player, NOT that a
        // log doc exists — a team of all-nil-doc players is an empty week, not pending.
        let resolvedSlugs = playerGameLogsStore.loadedSlugs
        let cal = appSettings.fantasyCalendar
        let elig = eligibility

        var result: [Int: [UUID: (FantasyTeamProduction, Bool)]] = [:]
        for week in schedule {
            let calendarWeek = week.index + 1           // schedule 0-based ↔ calendar 1-based
            guard let range = cal.weekDateRange(week: calendarWeek) else { continue }
            let interval = DateInterval(start: range.start, end: range.end)
            var teamMap: [UUID: (FantasyTeamProduction, Bool)] = [:]
            for team in memberTeams {
                let pair = FantasyWeeklySeason.teamWeekProduction(
                    rosterSlugs: team.playerSlugs,
                    logs: logs,
                    week: interval,
                    eligibility: elig,
                    teamId: team.id,
                    format: format,
                    resolvedSlugs: resolvedSlugs)
                teamMap[team.id] = pair
            }
            result[week.index] = teamMap
        }
        return result
    }

    /// Outcomes for every schedule week, scored from the precomputed productions.
    private var weekOutcomes: [FantasyWeekOutcome] {
        FantasyWeeklySeason.weekOutcomes(
            schedule: schedule,
            calendar: appSettings.fantasyCalendar,
            now: Date(),
            productionsByWeek: weeklyProductionsByWeek,
            format: format,
            customCategories: customCats)
    }

    /// Per-team records accumulated from COMPLETED + fully-resolved weeks only
    /// (spec §3: current week is provisional; pending matchups excluded).
    private var weeklyRecords: [UUID: FantasyRecord] {
        FantasyWeeklySeason.records(from: weekOutcomes)
    }

    /// Number of completed calendar weeks for the "Through Week N" caption.
    private var completedWeekCount: Int {
        FantasyWeeklySeason.completedWeeks(calendar: appSettings.fantasyCalendar, now: Date())
    }

    /// One player's raw per-game line under the active stat source (Dream Team scoring).
    private func dreamRaw(_ canon: String) -> RawPerGame? {
        switch appSettings.statSource {
        case .projected:
            return fantasyStore.value(for: canon).map { RawPerGame.projected($0, format: format) }
        case .live:
            guard let a = fantasyActualsStore.actuals(for: canon),
                  a.season == fantasyActualsStore.season else { return nil }
            return RawPerGame.live(a, format: format)
        }
    }

    /// Dream Team members with NO resolved player under the ACTIVE source (raw-rate
    /// poison guard — empty in non-Dream-Team leagues, so the standard path is untouched).
    private var dreamUnresolvedTeams: [FantasyTeam] {
        guard isDreamTeam else { return [] }
        return memberTeams.filter { team in
            !team.playerSlugs.contains { dreamRaw(FantasyValueStore.canonicalSlug($0)) != nil }
        }
    }

    private var productions: [UUID: FantasyTeamProduction] {
        if isDreamTeam {
            let own = FantasyDreamTeamScoring.ownership(teams: memberTeams)
            return FantasyDreamTeamScoring.productions(teams: memberTeams, ownership: own, raw: dreamRaw)
        }
        let src = source
        return Dictionary(memberTeams.map { ($0.id, src.production(for: $0, format: format)) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Member teams with NO live-season actuals for any rostered player, via the shared
    /// resolution rules in `FantasyLiveResolution` (canonical slug + season filter — the
    /// view does not re-derive them). A zero-resolved team's `.zero` production is
    /// poisonous in raw-rate space (`to = 0` beats every real team's ≤ 0), so live
    /// standings only compute when this is empty.
    private var liveUnresolvedTeams: [FantasyTeam] {
        FantasyLiveResolution.unresolvedTeams(teams: memberTeams,
                                              actuals: fantasyActualsStore.actualsBySlug,
                                              season: fantasyActualsStore.season)
    }

    /// Live is selected but NOT ONE rostered player on ANY team resolves (preseason /
    /// not yet populated). An honest note — NOT a silent fallback to projected, and
    /// NOT all-zero standings.
    private var liveNoData: Bool {
        guard appSettings.statSource == .live else { return false }
        return liveUnresolvedTeams.count == memberTeams.count
    }
    private var schedule: [FantasyScheduleWeek] {
        FantasyLeagueSchedule.resolved(teamIds: teamIds,
                                       regularSeasonWeeks: league?.rules.regularSeasonWeeks)
    }

    /// A resolved sample FantasyValue for the collection-empty decision (mirrors
    /// FantasyTeamDetailView — the decider needs a `FantasyValue?`).
    private var firstResolvedValue: FantasyValue? {
        memberTeams.flatMap(\.playerSlugs).lazy.compactMap { fantasyStore.value(for: $0) }.first
    }

    var body: some View {
        List {
            Section { banner }

            // Trading is a core manager activity — surface it as a top-level section
            // (mirroring the hosted league view) instead of burying it in the
            // Commissioner menu.
            if memberTeams.count >= 2 {
                Section("Trades") {
                    Button { showTrades = true } label: {
                        Label("Propose or Review Trades", systemImage: "arrow.left.arrow.right")
                    }
                    let pending = fantasyTradeStore.trades(for: leagueId).filter { !$0.status.isTerminal }.count
                    if pending > 0 {
                        Text("\(pending) pending trade\(pending == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if memberTeams.count < 2 {
                Section { guardCard }
            } else if appSettings.statSource == .live {
                if fantasyActualsStore.phase == .idle || fantasyActualsStore.phase == .loading {
                    Section { loadingRow }
                } else {
                    switch FantasyEmptyState.decide(phase: fantasyActualsStore.phase,
                                                    hasData: !liveNoData) {
                    case .loading:
                        Section { loadingRow }
                    case .collectionEmpty, .failed:   // a failed live fetch reads as "unavailable — switch to Projected"
                        Section { liveUnavailableCard }
                    case .playerMissing:
                        Section { liveNoDataCard }
                    case .data:
                        if liveUnresolvedTeams.isEmpty {
                            contentSections
                        } else {
                            Section { livePartialCard }
                        }
                    }
                }
            } else {
                switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: firstResolvedValue) {
                case .loading:
                    Section { loadingRow }
                case .collectionEmpty:
                    Section { Text("Fantasy values not available yet.").foregroundStyle(.secondary) }
                default:
                    // Dream Team scores in raw-rate space (an all-zero team's to=0 would
                    // win turnovers), so — like live — every team must resolve ≥1 player.
                    if !dreamUnresolvedTeams.isEmpty {
                        Section { dreamPartialCard }
                    } else {
                        contentSections
                    }
                }
            }
        }
        .navigationTitle(fantasyLeagueStore.league(leagueId)?.name ?? "League")
        .navigationBarTitleDisplayMode(.inline)
        // Weekly mode: load game logs for every rostered player the first time this
        // view appears (and whenever the roster changes). `PlayerGameLogsStore.load`
        // is incremental — already-loaded slugs are no-ops, so repeat calls are cheap.
        // We gate on `fantasyActualsStore.season` (same season source as ActualsStatSource)
        // so a season rollover clears and reloads without leaking stale logs.
        .task(id: isWeeklyMode ? allRosteredSlugs.sorted().joined() : "") {
            guard isWeeklyMode else { return }
            let season = fantasyActualsStore.season
            await playerGameLogsStore.load(slugs: allRosteredSlugs, season: season)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showLeagueSettings = true
                    } label: {
                        Label("League Settings", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        showDraftRoom = true
                    } label: {
                        Label("Draft Room", systemImage: "list.number")
                    }
                    // Trades moved to a top-level section in the body (above).
                    Button {
                        showManagers = true
                    } label: {
                        Label("Managers", systemImage: "person.2.badge.gearshape")
                    }
                    Button {
                        showSchedule = true
                    } label: {
                        Label("Edit Schedule", systemImage: "calendar.badge.clock")
                    }
                    if fantasyDraftStore.draft(for: leagueId) != nil {
                        Button(role: .destructive) {
                            confirmResetDraft = true
                        } label: {
                            Label("Reset Draft", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Commissioner", systemImage: "person.badge.key")
                }
            }
        }
        .confirmationDialog("Reset this league's draft? All picks are discarded (applied rosters stay on the teams).",
                            isPresented: $confirmResetDraft, titleVisibility: .visible) {
            Button("Reset Draft", role: .destructive) {
                fantasyDraftStore.resetDraft(leagueId: leagueId)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showLeagueSettings) {
            FantasyLeagueBuilderView(leagueId: leagueId)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyTeamStore)
                .environmentObject(fantasyDraftStore)
                .environmentObject(fantasyTradeStore)
        }
        .sheet(isPresented: $showDraftRoom) {
            FantasyDraftRoomView(leagueId: leagueId)
                .environmentObject(fantasyDraftStore)
                .environmentObject(fantasyTeamStore)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyStore)
                .environmentObject(teamsVM)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showTrades) {
            FantasyTradeReviewView(leagueId: leagueId)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyTeamStore)
                .environmentObject(fantasyTradeStore)
                .environmentObject(fantasyStore)
                .environmentObject(teamsVM)
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $showManagers) {
            FantasyManagersView(leagueId: leagueId)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyTeamStore)
        }
        .sheet(isPresented: $showSchedule) {
            FantasyScheduleEditorView(leagueId: leagueId)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyTeamStore)
                .environmentObject(appSettings)
        }
        .sheet(item: $selectedPairing) { p in
            // In weekly mode, tapping a past or current week row from the schedule passes
            // the week's real productions so the detail view shows weekly totals.
            // `selectedPairingWeekIndex` is set alongside `selectedPairing`.
            let weekStatus: FantasyWeekStatus? = selectedPairingWeekIndex.flatMap { wi in
                weekOutcomes.first(where: { $0.weekIndex == wi })?.status
            }
            let weekProds: [UUID: FantasyTeamProduction]? = {
                guard isWeeklyMode, let wi = selectedPairingWeekIndex else { return nil }
                // Future weeks have no games yet, so `teamWeekProduction` returns
                // resolved=true with all-zero totals once the logs are loaded. Showing
                // those zeros as "Week Totals" contradicts the header's "Projected"
                // badge, so fall through to the projected season-to-date matchup instead.
                guard let ws = weekStatus, ws != .future else { return nil }
                let map = weeklyProductionsByWeek[wi] ?? [:]
                // Only use weekly prods when both sides are resolved; fall back to season
                // productions for pending matchups so detail isn't empty.
                let homeResolved = map[p.home]?.1 ?? false
                let awayResolved = map[p.away]?.1 ?? false
                guard homeResolved && awayResolved else { return nil }
                return [p.home: map[p.home]?.0 ?? .zero,
                        p.away: map[p.away]?.0 ?? .zero]
            }()
            FantasyMatchupDetailView(
                pairing: p,
                productions: weekProds ?? productions,
                format: format,
                customCategories: customCats,
                nameFor: { fantasyTeamStore.team($0)?.name ?? "Team" },
                isLive: appSettings.statSource == .live,
                dreamTeam: isDreamTeam,
                weeklyTotalsMode: weekProds != nil,
                weekStatus: weekStatus)
        }
    }

    // MARK: pieces
    @ViewBuilder private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let seasonLine = fantasySeasonLine {
                Label(seasonLine, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            if isDreamTeam {
                Label("Dream Team — shared players' counting stats are split among the teams that roster them.",
                      systemImage: "person.3.sequence")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(rulesSummary).font(.caption.weight(.semibold))
            // Inline source control — the banners kept telling people to flip this in Settings.
            Picker("Scoring source", selection: $appSettings.statSource) {
                Text("Projected").tag(StatSourceMode.projected)
                Text("Live").tag(StatSourceMode.live)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
            switch appSettings.statSource {
            case .projected:
                Text("Projected mode — matchups reflect season-long projections, so results don't change week to week. Switch to Live above for real season-to-date scoring.")
                    .font(.caption).foregroundStyle(.secondary)
            case .live:
                if isWeeklyMode {
                    Text("Weekly mode — standings and matchups reflect real per-week box scores. Completed weeks count; the current week is provisional.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Live mode — standings reflect real season-to-date per-game production. (Season-to-date totals are static, so the round-robin doesn't vary week to week.)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Fantasy-season status from the shared league calendar — the same source
    /// that drives off/on-season. The "of Y" total is the league's OWN matchup-week
    /// count (the round-robin schedule length), NOT the raw NBA calendar span, so
    /// the banner agrees with the Schedule tab. nil when the calendar lacks windows.
    private var fantasySeasonLine: String? {
        let cal = appSettings.fantasyCalendar
        let matchupWeeks = schedule.count      // the league's actual matchup weeks
        switch cal.status(on: Date()) {
        case .unknown:
            return nil
        case .preseason(let days):
            if let start = cal.seasonStart {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "en_US_POSIX")
                fmt.timeZone = FantasyCalendar.zone
                fmt.dateFormat = "MMM d"
                let when = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
                return "Fantasy season starts \(when) (\(fmt.string(from: start)))"
            }
            return "Fantasy season hasn't started yet"
        case .active(let week, _):
            guard matchupWeeks > 0 else { return nil }
            if week > matchupWeeks { return "Fantasy regular season complete" }
            let range = cal.weekLabel(week: week).map { " (\($0))" } ?? ""
            return "Fantasy season: Week \(week) of \(matchupWeeks)\(range)"
        case .postseason:
            return "Fantasy regular season complete"
        }
    }

    /// One-line league setup summary (scoring · rosters · stakes).
    private var rulesSummary: String {
        var parts: [String] = []
        if let customCats {
            parts.append("Custom (\(customCats.count) cats)")
        } else {
            parts.append(format.displayName)
        }
        if let limits = league?.rules.limits {
            parts.append("Rosters \(limits.lineup)/\(limits.bench)/\(limits.ir)")
        }
        if let stakes = league?.stakes, stakes.isSet {
            let amount = stakes.buyIn.map { String(format: "$%.0f", $0) } ?? "Stakes"
            parts.append(stakes.platform.map { "\(amount) via \($0.displayName)" } ?? amount)
        }
        return parts.joined(separator: " · ")
    }

    /// The shared Standings/Schedule content (one definition — both source branches use it).
    @ViewBuilder private var contentSections: some View {
        Section { segmentPicker }
        if segment == .standings { standingsSections } else { scheduleSections }
    }

    @ViewBuilder private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading live data…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var liveUnavailableCard: some View {
        Text("Live data isn't available right now (not yet published, or the fetch failed). Projected mode still works — switch in Fantasy Settings.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var liveNoDataCard: some View {
        Text("No live data yet. Season-to-date scoring appears once these players have played regular-season games. Switch to Projected in Fantasy Settings to see season-long projections now.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var livePartialCard: some View {
        Text("Live standings need season-to-date data for every team. No rostered player has live data yet on: \(liveUnresolvedTeams.map(\.name).joined(separator: ", ")). Switch to Projected in Fantasy Settings to compare these teams now.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var dreamPartialCard: some View {
        Text("Dream Team standings need at least one resolved player on every team. Not resolved yet: \(dreamUnresolvedTeams.map(\.name).joined(separator: ", ")). Add players to those teams to see standings.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var guardCard: some View {
        Text("Add at least two teams to this league to see standings and matchups.")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var segmentPicker: some View {
        Picker("", selection: $segment) {
            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Standings
    @ViewBuilder private var standingsSections: some View {
        if isWeeklyMode {
            weeklyStandingsSections
        } else {
            projectedOrLiveStandingsSections
        }
    }

    @ViewBuilder private var projectedOrLiveStandingsSections: some View {
        let rows = FantasyStandings.standings(productions: productions, teamIds: teamIds,
                                              schedule: schedule, format: format,
                                              customCategories: customCats)
        Section("Standings") {
            HStack {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team")
                Spacer()
                Text("W-L-T").frame(width: 64, alignment: .trailing)
                Text(pointsScoring ? "Pts/G" : "Roto").frame(width: 52, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(rows) { row in standingRow(row) }
        }
        if format == .roto && customCats == nil {
            Section {
                Text("Roto standings sort by category rank-sum. The W-L column is an auxiliary head-to-head read (roto has no native head-to-head).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Weekly mode standings: records from COMPLETED + fully-resolved weeks only.
    @ViewBuilder private var weeklyStandingsSections: some View {
        let recs = weeklyRecords
        let n = completedWeekCount
        let header = n == 0 ? "Standings" : "Standings — Through Week \(n)"

        // Sort: wins desc → category diff desc → name asc (deterministic, matches existing engine)
        let sorted = teamIds.sorted { l, r in
            let rl = recs[l] ?? .init()
            let rr = recs[r] ?? .init()
            if rl.wins != rr.wins { return rl.wins > rr.wins }
            let dl = rl.categoryWins - rl.categoryLosses
            let dr = rr.categoryWins - rr.categoryLosses
            if dl != dr { return dl > dr }
            if rl.pointsFor != rr.pointsFor { return rl.pointsFor > rr.pointsFor }
            return (fantasyTeamStore.team(l)?.name ?? "") < (fantasyTeamStore.team(r)?.name ?? "")
        }

        Section(header) {
            HStack {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team")
                Spacer()
                Text("W-L-T").frame(width: 64, alignment: .trailing)
                Text(pointsScoring ? "FP" : "Cats").frame(width: 52, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(Array(sorted.enumerated()), id: \.element) { rank, teamId in
                weeklyStandingRow(rank: rank + 1, teamId: teamId, record: recs[teamId] ?? .init())
            }
        }

        // Local league approximate-history footnote (spec §UI local banner)
        Section {
            Text("Past weeks use current rosters — trades and adds are not reflected in historical results.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func weeklyStandingRow(rank: Int, teamId: UUID, record: FantasyRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(rank)").frame(width: 24, alignment: .leading)
                Text(fantasyTeamStore.team(teamId)?.name ?? "Removed team")
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("\(record.wins)-\(record.losses)-\(record.ties)")
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 64, alignment: .trailing)
                if pointsScoring {
                    Text(String(format: "%.0f", record.pointsFor))
                        .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 52, alignment: .trailing)
                } else {
                    Text("\(record.categoryWins)-\(record.categoryLosses)")
                        .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder private func standingRow(_ row: FantasyStandingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(row.rank)").frame(width: 24, alignment: .leading)
                Text(fantasyTeamStore.team(row.teamId)?.name ?? "Removed team")
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("\(row.record.wins)-\(row.record.losses)-\(row.record.ties)")
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 64, alignment: .trailing)
                Text(pointsScoring ? String(format: "%.1f", row.pointsPerGame)
                                   : String(format: "%.1f", row.rotoPoints))
                    .font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 52, alignment: .trailing)
            }
            if !pointsScoring {
                Text("Cats \(row.record.categoryWins)-\(row.record.categoryLosses)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Schedule
    /// "Week N" plus the real fantasy-date range when the calendar is available.
    private func weekHeader(_ index: Int) -> String {
        let n = index + 1
        if let range = appSettings.fantasyCalendar.weekLabel(week: n) {
            return "Week \(n) · \(range)"
        }
        return "Week \(n)"
    }

    @ViewBuilder private var scheduleSections: some View {
        if isWeeklyMode {
            weeklyScheduleSections
        } else {
            projectedScheduleSections
        }
    }

    @ViewBuilder private var projectedScheduleSections: some View {
        ForEach(schedule) { week in
            Section(weekHeader(week.index)) {
                ForEach(week.pairings) { p in
                    Button {
                        selectedPairingWeekIndex = nil
                        selectedPairing = p
                    } label: {
                        HStack {
                            Text("\(fantasyTeamStore.team(p.home)?.name ?? "Team")  vs  \(fantasyTeamStore.team(p.away)?.name ?? "Team")")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let bye = week.bye {
                    Text("Bye: \(fantasyTeamStore.team(bye)?.name ?? "Team")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        playoffsSection
    }

    /// Schedule in weekly mode: outcomes drive each row's appearance.
    @ViewBuilder private var weeklyScheduleSections: some View {
        let outcomes = weekOutcomes
        ForEach(schedule) { week in
            let outcome = outcomes.first(where: { $0.weekIndex == week.index })
            Section(weekHeader(week.index)) {
                ForEach(week.pairings) { p in
                    weeklyMatchupRow(pairing: p, weekIndex: week.index, outcome: outcome)
                }
                if let bye = week.bye {
                    Text("Bye: \(fantasyTeamStore.team(bye)?.name ?? "Team")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        playoffsSection
    }

    @ViewBuilder
    private func weeklyMatchupRow(pairing: FantasyMatchupPairing,
                                  weekIndex: Int,
                                  outcome: FantasyWeekOutcome?) -> some View {
        let homeName = fantasyTeamStore.team(pairing.home)?.name ?? "Team"
        let awayName = fantasyTeamStore.team(pairing.away)?.name ?? "Team"
        let status = outcome?.status ?? .future

        Button {
            selectedPairingWeekIndex = weekIndex
            selectedPairing = pairing
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(homeName)  vs  \(awayName)")
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.75)

                    // Outcome chip or status badge
                    weeklyMatchupChip(pairing: pairing, weekIndex: weekIndex,
                                      outcome: outcome, weekStatus: status)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func weeklyMatchupChip(pairing: FantasyMatchupPairing,
                                   weekIndex: Int,
                                   outcome: FantasyWeekOutcome?,
                                   weekStatus: FantasyWeekStatus) -> some View {
        switch weekStatus {
        case .future:
            // Future weeks: projected badge (existing behavior)
            Text("Projected")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.secondary)

        case .current:
            // Current in-progress week: show live provisional totals if resolved, else pending
            if let mo = outcome?.matchupOutcomes.first(where: { $0.pairing == pairing }) {
                if mo.status == .pending {
                    Text("Awaiting stats")
                        .font(.caption2).foregroundStyle(.orange)
                } else if let result = mo.result {
                    HStack(spacing: 4) {
                        matchupResultChip(result, home: pairing.home)
                        Text("In progress")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("In progress")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("In progress")
                    .font(.caption2).foregroundStyle(.secondary)
            }

        case .completed:
            // Completed weeks: real result chips or pending
            if let mo = outcome?.matchupOutcomes.first(where: { $0.pairing == pairing }) {
                if mo.status == .pending {
                    Text("Awaiting stats")
                        .font(.caption2).foregroundStyle(.orange)
                } else if let result = mo.result {
                    matchupResultChip(result, home: pairing.home)
                } else {
                    Text("Awaiting stats")
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Text("Awaiting stats")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    /// Category tally chip "6-3" or weekly fp totals chip, styled green/red for the winner.
    @ViewBuilder
    private func matchupResultChip(_ result: FantasyMatchupResult,
                                   home: UUID) -> some View {
        let isHomeTeam = true   // the chip always shows from the "home" perspective in pairing order
        let _ = isHomeTeam      // suppress unused warning
        Group {
            if result.isPoints {
                // Points: show weekly fp totals
                HStack(spacing: 2) {
                    Text(String(format: "%.0f", result.homePoints))
                        .foregroundStyle(result.outcome == .home ? .green :
                                         result.outcome == .away ? .red : .primary)
                    Text("–").foregroundStyle(.secondary)
                    Text(String(format: "%.0f", result.awayPoints))
                        .foregroundStyle(result.outcome == .away ? .green :
                                         result.outcome == .home ? .red : .primary)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
            } else {
                // Category: show "homeCatWins-awayCatWins" tally
                HStack(spacing: 2) {
                    Text("\(result.homeCategoryWins)")
                        .foregroundStyle(result.outcome == .home ? .green :
                                         result.outcome == .away ? .red : .primary)
                    Text("–").foregroundStyle(.secondary)
                    Text("\(result.awayCategoryWins)")
                        .foregroundStyle(result.outcome == .away ? .green :
                                         result.outcome == .home ? .red : .primary)
                }
                .font(.caption2.monospacedDigit().weight(.semibold))
            }
        }
    }

    /// Playoff preview: the configured bracket seeded by CURRENT standings (the
    /// full bracket simulation lands with the commissioner arc).
    @ViewBuilder private var playoffsSection: some View {
        if let pt = league?.rules.playoffTeams, pt >= 2 {
            Section("Playoffs") {
                let week = league?.rules.playoffStartWeek ?? (schedule.count + 1)
                Text("Top \(pt) seeds enter the bracket in week \(week).")
                    .font(.caption).foregroundStyle(.secondary)
                let rows = FantasyStandings.standings(productions: productions, teamIds: teamIds,
                                                      schedule: schedule, format: format,
                                                      customCategories: customCats)
                ForEach(rows.prefix(pt)) { row in
                    HStack {
                        Text("Seed \(row.rank)").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(fantasyTeamStore.team(row.teamId)?.name ?? "Removed team")
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
    }
}
