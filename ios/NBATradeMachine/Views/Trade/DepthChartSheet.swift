import SwiftUI

/// Post-trade depth chart for every team in the active trade. Uses the shared
/// `TeamDepthChartBuilder` (ESPN-primary, two-pass layer assignment, v2
/// TOT/OFF/DEF) — the same builder the team page uses — and renders it as the
/// layer-based `DepthChartLayersView` with per-layer Totals and league
/// green/red highlighting.
///
/// The post-trade roster is `vm.roster(for:) + vm.incomingPlayers(to:)`; the vm
/// roster already reflects outgoing players. Synthetic entries (signed free
/// agents / drafted prospects) are NOT `Player`s and are omitted from this
/// builder-based chart.
struct DepthChartSheet: View {
    @ObservedObject var vm: TradeMachineViewModel
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamId: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.trade.teams.isEmpty {
                    Text("Add teams to a trade to see depth charts.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    teamPicker
                    Divider()
                    if let team = currentTeam {
                        DepthChartLayersView(
                            columns: TeamDepthChartBuilder.columns(for: roster(for: team), cap: 5),
                            league: TeamDepthChartBuilder.leagueLayerStats(
                                rostersByTeam: teamsVM.playersByTeamId),
                            norms: normsVM.norms
                        )
                    }
                }
            }
            .navigationTitle("Depth Chart")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if selectedTeamId.isEmpty {
                    selectedTeamId = vm.trade.teams.first?.teamId ?? ""
                }
            }
        }
    }

    private var teamPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.trade.teams) { team in
                    Button {
                        selectedTeamId = team.teamId
                    } label: {
                        Text(team.teamId)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(team.teamId == selectedTeamId
                                          ? Color.accentColor.opacity(0.2)
                                          : Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var currentTeam: Team? {
        vm.trade.teams.first { $0.teamId == selectedTeamId } ?? vm.trade.teams.first
    }

    /// Post-trade roster for a team: players who stay plus incoming traded
    /// players. The vm roster already excludes outgoing players. Synthetic
    /// FA-signing / drafted-prospect entries are omitted (the builder is
    /// Player-based).
    private func roster(for team: Team) -> [Player] {
        vm.roster(for: team.teamId) + vm.incomingPlayers(to: team.teamId)
    }
}
