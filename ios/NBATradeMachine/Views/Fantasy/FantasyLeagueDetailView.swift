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
    @EnvironmentObject var appSettings: AppSettings

    let leagueId: UUID

    enum Segment: String, CaseIterable, Identifiable {
        case standings = "Standings", schedule = "Schedule"
        var id: String { rawValue }
    }
    @State private var segment: Segment = .standings
    @State private var selectedPairing: FantasyMatchupPairing?
    @State private var showLeagueSettings = false
    @State private var showDraftRoom = false
    @State private var confirmResetDraft = false
    @EnvironmentObject var fantasyDraftStore: FantasyDraftStore
    @EnvironmentObject var teamsVM: TeamsViewModel

    // MARK: Derived (recomputed each render — cheap; the engine is pure)
    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }

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

    private var productions: [UUID: FantasyTeamProduction] {
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
    private var schedule: [FantasyScheduleWeek] { FantasyLeagueSchedule.roundRobin(teamIds) }

    /// A resolved sample FantasyValue for the collection-empty decision (mirrors
    /// FantasyTeamDetailView — the decider needs a `FantasyValue?`).
    private var firstResolvedValue: FantasyValue? {
        memberTeams.flatMap(\.playerSlugs).lazy.compactMap { fantasyStore.value(for: $0) }.first
    }

    var body: some View {
        List {
            Section { banner }

            if memberTeams.count < 2 {
                Section { guardCard }
            } else if appSettings.statSource == .live {
                if fantasyActualsStore.phase == .idle || fantasyActualsStore.phase == .loading {
                    Section { loadingRow }
                } else {
                    switch FantasyEmptyState.decide(phase: fantasyActualsStore.phase,
                                                    hasData: !liveNoData) {
                    case .collectionEmpty:
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
                case .collectionEmpty:
                    Section { Text("Fantasy values not available yet.").foregroundStyle(.secondary) }
                default:
                    contentSections
                }
            }
        }
        .navigationTitle(fantasyLeagueStore.league(leagueId)?.name ?? "League")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $selectedPairing) { p in
            FantasyMatchupDetailView(pairing: p, productions: productions, format: format,
                                     customCategories: customCats,
                                     nameFor: { fantasyTeamStore.team($0)?.name ?? "Team" },
                                     isLive: appSettings.statSource == .live)
        }
    }

    // MARK: pieces
    @ViewBuilder private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rulesSummary).font(.caption.weight(.semibold))
            switch appSettings.statSource {
            case .projected:
                Text("Projected mode — matchups reflect season-long projections, so results don't change week to week. Switch to Live in Fantasy Settings for real season-to-date scoring.")
                    .font(.caption).foregroundStyle(.secondary)
            case .live:
                Text("Live mode — standings reflect real season-to-date per-game production. (Season-to-date totals are static, so the round-robin doesn't vary week to week.)")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

    @ViewBuilder private func standingRow(_ row: FantasyStandingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(row.rank)").frame(width: 24, alignment: .leading)
                Text(fantasyTeamStore.team(row.teamId)?.name ?? "Removed team")
                Spacer()
                Text("\(row.record.wins)-\(row.record.losses)-\(row.record.ties)")
                    .font(.subheadline.monospacedDigit()).frame(width: 64, alignment: .trailing)
                Text(pointsScoring ? String(format: "%.1f", row.pointsPerGame)
                                   : String(format: "%.1f", row.rotoPoints))
                    .font(.subheadline.monospacedDigit()).frame(width: 52, alignment: .trailing)
            }
            if !pointsScoring {
                Text("Cats \(row.record.categoryWins)-\(row.record.categoryLosses)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Schedule
    @ViewBuilder private var scheduleSections: some View {
        ForEach(schedule) { week in
            Section("Week \(week.index + 1)") {
                ForEach(week.pairings) { p in
                    Button { selectedPairing = p } label: {
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
