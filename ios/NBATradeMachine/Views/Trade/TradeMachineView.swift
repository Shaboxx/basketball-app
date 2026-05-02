import SwiftUI

struct TradeMachineView: View {
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @StateObject private var vm = TradeMachineViewModel()
    @State private var selectedTeamId: String = ""
    @State private var showingAddTeam = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.trade.teams.count < 2 {
                    InitialTeamSelectionView(vm: vm)
                        .navigationTitle("Trade Machine")
                } else {
                    activeTradeView
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .navigationDestination(for: Player.self) { player in
                PlayerDetailView(player: player)
            }
        }
        .onAppear {
            vm.configure(teamsVM: teamsVM, rulesVM: rulesVM)
        }
        .alert(
            "Trade Warning",
            isPresented: Binding(
                get: { vm.alertMessage != nil },
                set: { if !$0 { vm.alertMessage = nil } }
            ),
            presenting: vm.alertMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showingAddTeam) {
            AddTeamSheet(vm: vm) { id in
                selectedTeamId = id
            }
        }
    }

    private var activeTradeView: some View {
        VStack(spacing: 0) {
            Toggle("Offseason mode (next season)", isOn: $vm.isOffseason)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))

            TradeTabBar(
                teams: vm.trade.teams,
                selection: Binding(
                    get: { effectiveSelection },
                    set: { selectedTeamId = $0 }
                ),
                canAddTeam: vm.trade.teams.count < TradeMachineViewModel.maxTeams,
                onAddTap: { showingAddTeam = true }
            )

            Divider()

            ScrollView {
                if let team = currentTeam {
                    VStack(spacing: 16) {
                        TeamTradeTabContent(team: team, vm: vm)
                        actionButtons.padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                vm.validate()
            } label: {
                Label("Validate Trade", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                vm.reset()
                selectedTeamId = ""
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }

    private var effectiveSelection: String {
        if vm.trade.teamIds.contains(selectedTeamId) { return selectedTeamId }
        return vm.trade.teams.first?.teamId ?? ""
    }

    private var currentTeam: Team? {
        vm.trade.teams.first { $0.teamId == effectiveSelection }
    }
}
