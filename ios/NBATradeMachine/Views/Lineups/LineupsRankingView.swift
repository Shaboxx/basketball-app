import SwiftUI

/// Ranked list of every team's starting five (Σ dispTotal), each rendered as a
/// card in the SAME cell format as the "Create Lineups" pages (player portrait +
/// name + SwishScore OVR/OFF/DEF, colored vs the league's layer-0 distribution).
/// Every card has a "Customize Lineups" button that pushes that team's Lineup
/// Maker, and tapping the team header pushes that team's full depth chart.
/// Derives on the fly from the in-memory league roster (no new fetch).
struct LineupsRankingView: View {
    @EnvironmentObject private var teamsVM: TeamsViewModel
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore
    @EnvironmentObject private var footerState: FooterState

    @Binding var path: NavigationPath

    /// Push target for a team's Lineup Maker. Distinct type from `Team` (whose
    /// destination is the depth chart) so the two taps route to different screens.
    private struct CustomizeTarget: Hashable { let teamId: String }

    private static let zero = TeamDepthChartBuilder.MetricStats(mean: 0, std: 0)

    private var result: LineupRankingResult {
        LineupRankingLogic.rank(teams: teamsVM.teams,
                                rostersByTeamId: teamsVM.playersByTeamId)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    PlayerListSkeleton()            // reuse the shared row skeleton
                } else {
                    let res = result
                    if res.ranked.isEmpty {
                        empty
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(res.ranked) { row in
                                teamCard(row)
                            }
                        }
                        .padding(.vertical, 10)
                        footnote(res.excluded)
                    }
                }
            }
            .reportsFooterScroll(footerState)
            .navigationTitle("")   // app header already reads "Lineups"
            .navigationBarTitleDisplayMode(.inline)
            // Team header tap → that team's depth chart.
            .navigationDestination(for: Team.self) { team in
                depthChart(for: team)
            }
            // "Customize Lineups" → that team's Lineup Maker (create-lineups page).
            .navigationDestination(for: CustomizeTarget.self) { target in
                lineupMaker(for: target.teamId)
            }
            // Player cells inside the depth chart push PlayerDetailView.
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

    private func teamCard(_ row: LineupRankRow) -> some View {
        let stats = teamsVM.leagueLayerStats.playerByLayer[0]
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Player.fmtVal(row.total))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                        Text("TOTAL").font(.system(size: 8)).foregroundStyle(.secondary)
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

            // Customize → that team's Lineup Maker.
            NavigationLink(value: CustomizeTarget(teamId: row.team.teamId)) {
                Label("Customize Lineups", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    /// One starter cell mirroring `LineupMakerView`/`DepthChartLayersView`:
    /// position label + portrait + name + colored OVR/OFF/DEF.
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
