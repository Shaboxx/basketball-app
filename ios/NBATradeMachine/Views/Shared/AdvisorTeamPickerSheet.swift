import SwiftUI

/// The settings-gear "Ask Advisor" entry point. The gear carries no team context, so this
/// sheet first picks a team, then presents the existing Trade Advisor flow for that team.
/// A chosen proposal opens the Trade Machine seeded with it — mirroring the old contextual
/// `TeamDetailView` entry, now consolidated here.
struct AdvisorTeamPickerSheet: View {
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @EnvironmentObject var picksVM: PicksViewModel
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var appSettings: AppSettings
    // Forwarded into the TradeMachineView cover below (which now requires it for its
    // PlayerDetailView pushes); supplied by ContentView's Ask-Advisor sheet.
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @Environment(\.dismiss) private var dismiss

    /// The team whose advisor sheet is open (drives `.sheet(item:)`).
    @State private var advisorTeam: Team?
    /// A proposal the user chose to open in the Trade Machine.
    @State private var proposalToOpen: AdvisorProposal?

    var body: some View {
        NavigationStack {
            List(teamsVM.teams) { team in
                Button {
                    advisorTeam = team
                } label: {
                    HStack(spacing: 12) {
                        TeamLogoMark(teamId: team.teamId, size: 28, showsAlias: false)
                        Text(team.fullName)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Ask Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(item: $advisorTeam) { team in
            TradeAdvisorSheet(
                // Single-team entry: a 1-element set is treated as "open" (no partner constraint).
                viewModel: TradeAdvisorViewModel(team: team.tricode, service: FirebaseAdvisorService(),
                                                 teamSet: [team.tricode]),
                onApply: { proposal in
                    advisorTeam = nil
                    proposalToOpen = proposal
                })
            .environmentObject(teamsVM)
        }
        .fullScreenCover(item: $proposalToOpen) { proposal in
            TradeMachineView(initialProposal: proposal)
                .environmentObject(teamsVM)
                .environmentObject(rulesVM)
                .environmentObject(picksVM)
                .environmentObject(normsVM)
                .environmentObject(appSettings)
                .environmentObject(fantasyStore)
        }
    }
}
