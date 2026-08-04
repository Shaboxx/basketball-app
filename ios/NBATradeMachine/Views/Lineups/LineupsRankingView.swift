import SwiftUI

/// Ranked list of every team's starting five (Σ dispTotal / dispOff / dispDef),
/// each rendered as a card in the SAME cell format as the "Create Lineups" pages
/// (player portrait + name + SwishScore OVR/OFF/DEF, colored vs the league's
/// layer-0 distribution). Cards show TOT/OFF/DEF colored relative to the mean
/// across all ranked teams. A segmented picker re-sorts by Total/Offense/Defense.
/// Each card has a compact "Customize {name}'s Lineups" button and a
/// "Starter Lineup Analysis" button. Derives on the fly from the in-memory
/// league roster (no new fetch).
struct LineupsRankingView: View {
    @EnvironmentObject private var teamsVM: TeamsViewModel
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore
    @EnvironmentObject private var footerState: FooterState

    @Binding var path: NavigationPath

    /// Sort axis for the ranked list.
    @State private var sortAxis: SortAxis = .total
    private enum SortAxis: String, CaseIterable, Identifiable {
        case total    = "Total"
        case offense  = "Offense"
        case defense  = "Defense"
        var id: String { rawValue }
        var label: String { rawValue }
    }

    /// Push target for a team's Lineup Maker. Distinct type from `Team` (whose
    /// destination is the depth chart) so the two taps route to different screens.
    private struct CustomizeTarget: Hashable { let teamId: String }

    /// Push target for the starter lineup breakdown analysis.
    private struct StarterAnalysisTarget: Hashable { let teamId: String }

    private static let zero = TeamDepthChartBuilder.MetricStats(mean: 0, std: 0)

    /// Base ranking (always sorted by total desc) re-sorted and re-numbered
    /// according to the current `sortAxis`. Nil-axis rows sink to the bottom
    /// when sorting by Offense or Defense.
    private var sortedResult: LineupRankingResult {
        let base = LineupRankingLogic.rank(teams: teamsVM.teams,
                                           rostersByTeamId: teamsVM.playersByTeamId)
        let resorted: [LineupRankRow]
        switch sortAxis {
        case .total:
            resorted = base.ranked
        case .offense:
            resorted = base.ranked.sorted { a, b in
                switch (a.off, b.off) {
                case (.none, .none):
                    if a.team.fullName != b.team.fullName { return a.team.fullName < b.team.fullName }
                    return a.team.teamId < b.team.teamId
                case (.none, _): return false   // nil sinks to bottom
                case (_, .none): return true    // non-nil floats to top
                case let (.some(av), .some(bv)):
                    if av != bv { return av > bv }
                    if a.team.fullName != b.team.fullName { return a.team.fullName < b.team.fullName }
                    return a.team.teamId < b.team.teamId
                }
            }
        case .defense:
            resorted = base.ranked.sorted { a, b in
                switch (a.def, b.def) {
                case (.none, .none):
                    if a.team.fullName != b.team.fullName { return a.team.fullName < b.team.fullName }
                    return a.team.teamId < b.team.teamId
                case (.none, _): return false   // nil sinks to bottom
                case (_, .none): return true    // non-nil floats to top
                case let (.some(av), .some(bv)):
                    if av != bv { return av > bv }
                    if a.team.fullName != b.team.fullName { return a.team.fullName < b.team.fullName }
                    return a.team.teamId < b.team.teamId
                }
            }
        }
        let renumbered = resorted.enumerated().map { i, r in
            LineupRankRow(rank: i + 1, team: r.team, starters: r.starters,
                          total: r.total, off: r.off, def: r.def)
        }
        return LineupRankingResult(ranked: renumbered, excluded: base.excluded)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    PlayerListSkeleton()
                } else {
                    let res = sortedResult
                    if res.ranked.isEmpty {
                        empty
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(res.ranked) { row in
                                teamCard(row, ranked: res.ranked)
                            }
                        }
                        .padding(.vertical, 10)
                        footnote(res.excluded)
                    }
                }
            }
            .reportsFooterScroll(footerState)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortAxis) {
                            ForEach(SortAxis.allCases) { axis in
                                Text(axis.label).tag(axis)
                            }
                        }
                    } label: {
                        Label("Sort: \(sortAxis.label)",
                              systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
            }
            // Team header tap → that team's depth chart.
            .navigationDestination(for: Team.self) { team in
                depthChart(for: team)
            }
            // "Customize Lineups" → that team's Lineup Maker.
            .navigationDestination(for: CustomizeTarget.self) { target in
                lineupMaker(for: target.teamId)
            }
            // "Starter Lineup Analysis" → LineupBreakdownView for that team's starters.
            .navigationDestination(for: StarterAnalysisTarget.self) { target in
                starterAnalysis(for: target.teamId)
            }
            // Player cells inside depth chart / breakdown push PlayerDetailView.
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
                    .environmentObject(teamsVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
            }
        }
        .task { await teamsVM.load() }
    }

    // MARK: - Team card

    private func teamCard(_ row: LineupRankRow, ranked: [LineupRankRow]) -> some View {
        let stats = teamsVM.leagueLayerStats.playerByLayer[0]

        // Mean over non-nil off/def values only (avoids pulling nil into the average).
        let meanTot: Double = {
            guard !ranked.isEmpty else { return 0 }
            return ranked.map(\.total).reduce(0, +) / Double(ranked.count)
        }()
        let meanOff: Double = {
            let vals = ranked.compactMap(\.off)
            return vals.isEmpty ? 0.0 : vals.reduce(0, +) / Double(vals.count)
        }()
        let meanDef: Double = {
            let vals = ranked.compactMap(\.def)
            return vals.isEmpty ? 0.0 : vals.reduce(0, +) / Double(vals.count)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            // Header — tap for depth chart.
            NavigationLink(value: row.team) {
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    TeamLogoMark(teamId: row.team.teamId, size: 34, showsAlias: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.team.fullName).font(.subheadline.weight(.semibold))
                        Text("Tap for depth chart")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // TOT always colored; OFF/DEF show "—" when nil.
                    HStack(spacing: 10) {
                        scoreCol("TOT", row.total, axisColor(row.total, mean: meanTot))
                        scoreColOptional("OFF", row.off, mean: meanOff)
                        scoreColOptional("DEF", row.def, mean: meanDef)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Starters in the create-lineup cell format (portrait + SwishScore).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(zip(TeamDepthChartBuilder.positions, row.starters)), id: \.0) { pos, player in
                        starterCell(pos: pos, player: player, stats: stats)
                    }
                }
            }

            // Button row: Customize + Starter Lineup Analysis side-by-side.
            HStack(spacing: 8) {
                NavigationLink(value: CustomizeTarget(teamId: row.team.teamId)) {
                    Text("Customize \(row.team.tricode) Lineups")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)

                NavigationLink(value: StarterAnalysisTarget(teamId: row.team.teamId)) {
                    Text("Starter Lineup Analysis")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    /// One starter cell mirroring `LineupMakerView`/`DepthChartLayersView`.
    private func starterCell(pos: String, player: Player,
                             stats: (tot: TeamDepthChartBuilder.MetricStats,
                                     off: TeamDepthChartBuilder.MetricStats,
                                     def: TeamDepthChartBuilder.MetricStats)?) -> some View {
        VStack(spacing: 2) {
            Text(pos)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            HeadshotImage(slug: player.slug, size: 30)
            Text(player.name)
                .font(.system(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("SwishScore")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            metricLine("OVR", player.dispTotal,
                       TeamDepthChartBuilder.highlight(player.dispTotal, stats?.tot ?? Self.zero))
            metricLine("OFF", player.dispOff,
                       TeamDepthChartBuilder.highlight(player.dispOff, stats?.off ?? Self.zero))
            metricLine("DEF", player.dispDef,
                       TeamDepthChartBuilder.highlight(player.dispDef, stats?.def ?? Self.zero))
        }
        .padding(6)
        .frame(width: 66, alignment: .top)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color(.separator), lineWidth: 0.5))
    }

    // MARK: - Push destinations

    private func depthChart(for team: Team) -> some View {
        let roster = teamsVM.playersByTeamId[team.teamId] ?? []
        return DepthChartLayersView(
            columns: TeamDepthChartBuilder.columns(for: roster, cap: 5),
            league: teamsVM.leagueLayerStats,
            norms: normsVM.norms,
            roster: roster
        )
        .navigationTitle(team.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lineupMaker(for teamId: String) -> some View {
        let roster = teamsVM.playersByTeamId[teamId] ?? []
        return LineupMakerView(roster: roster,
                               league: teamsVM.leagueLayerStats,
                               norms: normsVM.norms)
    }

    private func starterAnalysis(for teamId: String) -> some View {
        let roster   = teamsVM.playersByTeamId[teamId] ?? []
        let starters = LineupRankingLogic.starters(for: roster).compactMap { $0 }
        return LineupBreakdownView(
            players: starters,
            norms:   normsVM.norms,
            impacts: starters.map { $0.thetaV2?.theta },
            tier:    "starters"
        )
        .navigationTitle("Starter Lineup Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .environmentObject(teamsVM)
        .environmentObject(normsVM)
        .environmentObject(appSettings)
        .environmentObject(fantasyStore)
    }

    // MARK: - Axis coloring helpers

    /// Green when value >= mean across ranked teams; red otherwise.
    private func axisColor(_ value: Double, mean: Double) -> Color {
        value >= mean ? .green : .red
    }

    /// Trailing-aligned label+value column for the header score strip (non-nil value).
    private func scoreCol(_ label: String, _ val: Double, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Player.fmtVal(val))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    /// Trailing-aligned label+em-dash column rendered in secondary color when
    /// the axis value is nil (data unavailable for this team).
    private func scoreColNil(_ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\u{2014}")   // em dash
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    /// Renders scoreCol when val is present, scoreColNil when absent.
    @ViewBuilder
    private func scoreColOptional(_ label: String, _ val: Double?, mean: Double) -> some View {
        if let v = val {
            scoreCol(label, v, axisColor(v, mean: mean))
        } else {
            scoreColNil(label)
        }
    }

    // MARK: - Cell helpers (mirror DepthChartLayersView)

    private func metricLine(_ label: String, _ value: Double?,
                            _ highlight: TeamDepthChartBuilder.Highlight) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text(Player.fmtVal(value))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(color(for: highlight))
        }
    }

    private func color(for highlight: TeamDepthChartBuilder.Highlight) -> Color {
        switch highlight {
        case .above: return .green
        case .below: return .red
        case .neutral: return .primary
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.number").font(.largeTitle).foregroundStyle(.secondary)
            Text("No complete starting lineups available.").font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func footnote(_ excluded: [Team]) -> some View {
        if !excluded.isEmpty {
            Text("Not enough data for: " + excluded.map { $0.name }.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
    }
}
