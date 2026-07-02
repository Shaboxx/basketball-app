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

    // MARK: Derived (recomputed each render — cheap; the engine is pure)
    private var format: FantasyFormat { appSettings.fantasyFormat }

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

    /// Live is selected but NOT ONE rostered player resolves to a live-season actuals doc
    /// (preseason / not yet populated). We show an honest note — NOT a silent fallback to
    /// projected, and NOT all-zero standings.
    private var liveNoData: Bool {
        guard appSettings.statSource == .live else { return false }
        return memberTeams.flatMap(\.playerSlugs)
            .compactMap { fantasyActualsStore.actuals(for: $0) }
            .filter { $0.season == fantasyActualsStore.season }
            .isEmpty
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
                if liveNoData {
                    Section { liveNoDataCard }
                } else {
                    Section { segmentPicker }
                    if segment == .standings { standingsSections } else { scheduleSections }
                }
            } else {
                switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: firstResolvedValue) {
                case .collectionEmpty:
                    Section { Text("Fantasy values not available yet.").foregroundStyle(.secondary) }
                default:
                    Section { segmentPicker }
                    if segment == .standings { standingsSections } else { scheduleSections }
                }
            }
        }
        .navigationTitle(fantasyLeagueStore.league(leagueId)?.name ?? "League")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPairing) { p in
            FantasyMatchupDetailView(pairing: p, productions: productions, format: format,
                                     nameFor: { fantasyTeamStore.team($0)?.name ?? "Team" },
                                     isLive: appSettings.statSource == .live)
        }
    }

    // MARK: pieces
    @ViewBuilder private var banner: some View {
        switch appSettings.statSource {
        case .projected:
            Text("Projected mode — matchups reflect season-long projections, so results don't change week to week. Switch to Live in Fantasy Settings for real season-to-date scoring.")
                .font(.caption).foregroundStyle(.secondary)
        case .live:
            Text("Live mode — standings reflect real season-to-date per-game production. (Season-to-date totals are static, so the round-robin doesn't vary week to week.)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var liveNoDataCard: some View {
        Text("No live data yet. Season-to-date scoring appears once these players have played regular-season games. Switch to Projected in Fantasy Settings to see season-long projections now.")
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
                                              schedule: schedule, format: format)
        Section("Standings") {
            HStack {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Team")
                Spacer()
                Text("W-L-T").frame(width: 64, alignment: .trailing)
                Text(format.isPoints ? "Pts/G" : "Roto").frame(width: 52, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(rows) { row in standingRow(row) }
        }
        if format == .roto {
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
                Text(format.isPoints ? String(format: "%.1f", row.pointsPerGame)
                                     : String(format: "%.1f", row.rotoPoints))
                    .font(.subheadline.monospacedDigit()).frame(width: 52, alignment: .trailing)
            }
            if !format.isPoints {
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
    }
}
