import SwiftUI

struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    // Forwarded into the depth-chart sheet (a sheet does NOT inherit the environment) so the
    // player rows there can push PlayerDetailView, which needs all four.
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @State private var showingDepthChart = false
    @State private var showingStartersBreakdown = false

    var body: some View {
        let roster = teamsVM.players(for: team.teamId)
        let total = teamsVM.totalSalary(for: team.teamId)
        // Shared by the Starting Lineup section AND the depth-chart sheet, so the
        // panel's five + score always match the chart's Starters row exactly.
        let columns = TeamDepthChartBuilder.columns(for: roster, cap: 5)

        List {
            Section {
                HStack(spacing: 16) {
                    TeamLogoMark(teamId: team.teamId, size: 72, aliasFont: .caption)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(team.fullName).font(.title2.bold())
                        Text("\(team.conference) · \(team.division)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            rosterValueSection(roster: roster)
            startingLineupSection(columns: columns)

            Section("Roster (\(roster.count))") {
                ForEach(roster) { p in
                    NavigationLink(value: p) {
                        HStack {
                            HeadshotImage(slug: p.slug, size: 36)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.subheadline)
                                Text(p.position).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.display(p.currentSalary))
                                    .font(.caption.monospacedDigit())
                                if p.hasDisplayValue {
                                    Text(rosterRowValue(p))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Total Team Salary") {
                HStack {
                    Text(Money.display(total)).font(.title3.bold().monospacedDigit())
                    Spacer()
                    if let rules = rulesVM.rules {
                        CapTierBadge(tier: rules.tier(for: total))
                    }
                }
            }

            AdRow()   // bottom-of-page banner slot; self-hides when ads are off
        }
        .navigationDestination(for: Player.self) { p in
            PlayerDetailView(player: p)
                .environmentObject(teamsVM)
                .environmentObject(normsVM)
                .environmentObject(appSettings)
                .environmentObject(fantasyStore)
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Depth Chart") { showingDepthChart = true }
            }
        }
        .sheet(isPresented: $showingDepthChart) {
            NavigationStack {
                DepthChartLayersView(
                    columns: columns,
                    league: teamsVM.leagueLayerStats,   // cached; rebuilt only on data reload
                    norms: normsVM.norms,
                    roster: roster
                )
                .navigationTitle("Depth Chart")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Player.self) { p in
                    PlayerDetailView(player: p)
                        .environmentObject(teamsVM)
                        .environmentObject(normsVM)
                        .environmentObject(appSettings)
                        .environmentObject(fantasyStore)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingDepthChart = false }
                    }
                }
            }
            // The sheet strips the environment; re-inject so both the depth-chart's own
            // player pushes AND DepthChartLayersView's breakdown sub-sheet can present
            // PlayerDetailView (which reads all four).
            .environmentObject(teamsVM)
            .environmentObject(normsVM)
            .environmentObject(appSettings)
            .environmentObject(fantasyStore)
        }
        .sheet(isPresented: $showingStartersBreakdown) {
            let five = starters(columns)
            NavigationStack {
                LineupBreakdownView(
                    players: five,
                    norms: normsVM.norms,
                    impacts: five.map { $0.thetaBoard?.total },
                    tier: "starters"
                )
                .navigationDestination(for: Player.self) { p in
                    PlayerDetailView(player: p)
                        .environmentObject(teamsVM)
                        .environmentObject(normsVM)
                        .environmentObject(appSettings)
                        .environmentObject(fantasyStore)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingStartersBreakdown = false }
                    }
                }
            }
            // The sheet strips the environment; re-inject so the breakdown's
            // player pushes can present PlayerDetailView (which reads all four).
            .environmentObject(teamsVM)
            .environmentObject(normsVM)
            .environmentObject(appSettings)
            .environmentObject(fantasyStore)
        }
    }

    /// Summary band: sum of OFF/DEF value across the roster (incoming-style
    /// rollup). Hidden when no player on the roster has a display value yet —
    /// avoids showing 0.0 for the handful of teams whose roster still has
    /// only Tier-A docs.
    @ViewBuilder
    private func rosterValueSection(roster: [Player]) -> some View {
        let rollup = currentRollup()
        if rollup.rated > 0 {
            Section("Roster Latent Value") {
                HStack(spacing: 16) {
                    rollupCell("OFF Σ", signed(rollup.off))
                    rollupCell("DEF Σ", signed(rollup.def))
                    rollupCell("Coverage", "\(rollup.rated) / \(rollup.total)")
                }
            }
        }
    }

    private func currentRollup() -> (off: Double, def: Double, rated: Int, total: Int) {
        if AppConfig.weightedOvrEnabled {
            let wr = teamsVM.weightedRollup(for: team.teamId)
            return (wr.off, wr.def, wr.rated, wr.total)
        } else {
            return teamsVM.latentValueRollup(for: team.teamId)
        }
    }

    private func rollupCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    /// The depth chart's Starters row surfaced on the team page: the five
    /// starting-layer players (PG-SG-SF-PF-C) plus that layer's summed
    /// TOT/OFF/DEF lineup score — the same numbers as the Starters Lineup cell
    /// in the depth chart, colored against the league's starters-layer
    /// distribution. Tapping opens the generated LineupBreakdownView for the
    /// five. Auto-hides when no starter cell fills (no canonical-position
    /// players on the roster yet).
    @ViewBuilder
    private func startingLineupSection(columns: [String: ColumnResult]) -> some View {
        let five = starters(columns)
        if !five.isEmpty {
            let sums = TeamDepthChartBuilder.layerTotals(columns, layer: 0)
            let stats = teamsVM.leagueLayerStats.totalByLayer[0]
            Section("Starting Lineup") {
                Button {
                    showingStartersBreakdown = true
                } label: {
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(five) { p in
                                HeadshotImage(slug: p.slug, size: 36)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("SwishScore")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Lineup Analysis")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                            HStack(spacing: 12) {
                                scoreCell("OVR", sums.tot, stats?.tot)
                                scoreCell("OFF", sums.off, stats?.off)
                                scoreCell("DEF", sums.def, stats?.def)
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// First-layer (Starters) player of each filled position column, in
    /// PG-SG-SF-PF-C order. Mirrors DepthChartLayersView.layerPlayers(0).
    private func starters(_ columns: [String: ColumnResult]) -> [Player] {
        TeamDepthChartBuilder.positions.compactMap { pos -> Player? in
            guard let shown = columns[pos]?.shown, !shown.isEmpty else { return nil }
            return shown[0].player
        }
    }

    private func scoreCell(_ label: String, _ value: Double,
                           _ stats: TeamDepthChartBuilder.MetricStats?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(Player.fmtVal(value))
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(scoreColor(TeamDepthChartBuilder.highlight(
                    value, stats ?? TeamDepthChartBuilder.MetricStats(mean: 0, std: 0))))
        }
    }

    private func scoreColor(_ h: TeamDepthChartBuilder.Highlight) -> Color {
        switch h {
        case .above: return .green
        case .below: return .red
        case .neutral: return .primary
        }
    }

    private func rosterRowValue(_ p: Player) -> String {
        let t = Player.fmtVal(p.dispTotal)
        let o = Player.fmtVal(p.dispOff)
        let d = Player.fmtVal(p.dispDef)
        return "TOT \(t) · OFF \(o) · DEF \(d)"
    }

    private func signed(_ v: Double) -> String {
        Player.fmtVal(v)
    }
}
