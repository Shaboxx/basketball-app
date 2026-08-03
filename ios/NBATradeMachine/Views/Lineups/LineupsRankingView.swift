import SwiftUI

/// Ranked, tappable list of every team's starting five (Σ dispTotal). Derives
/// on the fly from the in-memory league roster (no new fetch). Tapping a row
/// pushes the existing LineupBreakdownView seeded with those five starters.
struct LineupsRankingView: View {
    @EnvironmentObject private var teamsVM: TeamsViewModel
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore
    @EnvironmentObject private var footerState: FooterState

    @Binding var path: NavigationPath

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
                        LazyVStack(spacing: 0) {
                            ForEach(res.ranked) { row in
                                NavigationLink(value: row) { rowView(row) }
                                    .buttonStyle(.plain)
                                Divider().opacity(0.25)
                            }
                        }
                        .padding(.top, 4)
                        footnote(res.excluded)
                    }
                }
            }
            .reportsFooterScroll(footerState)
            .navigationTitle("")   // app header already reads "Lineups"
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: LineupRankRow.self) { row in
                LineupBreakdownView(
                    players: row.starters,
                    norms: normsVM.norms,
                    impacts: row.starters.map { $0.thetaV2?.theta },
                    tier: "starters"
                )
                .navigationDestination(for: Player.self) { p in
                    PlayerDetailView(player: p)
                        .environmentObject(teamsVM)
                        .environmentObject(normsVM)
                        .environmentObject(appSettings)
                        .environmentObject(fantasyStore)
                }
            }
        }
        .task { await teamsVM.load() }
    }

    private func rowView(_ row: LineupRankRow) -> some View {
        HStack(spacing: 12) {
            Text("\(row.rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            TeamLogoMark(teamId: row.team.teamId, size: 38, showsAlias: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.team.fullName).font(.subheadline.weight(.semibold))
                Text(row.starters.map { $0.name }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Player.fmtVal(row.total))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                Text("TOTAL").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
        .padding(.horizontal)
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
