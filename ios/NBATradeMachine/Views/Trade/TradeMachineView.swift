import SwiftUI

struct TradeMachineView: View {
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @EnvironmentObject var picksVM: PicksViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = TradeMachineViewModel()

    /// Pre-selected teams the machine should open with (from the Teams-grid
    /// selection mode). When non-empty, `setTeams` runs on appear so the view
    /// lands straight on `activeTradeView` instead of the picker.
    var initialTeams: [Team] = []

    /// A complete proposal (from the Trade Advisor) to seed the machine with.
    /// When provided, it takes precedence over `initialTeams` — the applier
    /// seats the teams itself and applies the moves.
    var initialProposal: AdvisorProposal? = nil

    @State private var selectedTeamId: String = ""
    @State private var showingAddTeam = false
    @State private var showingHistory = false
    @State private var showingDepthChart = false
    @State private var showAdvisor = false
    @State private var confirmationSnapshot: ConfirmationSnapshot?

    /// Snapshot captured at validation time so the confirmation sheet shows
    /// the trade as it was when the user tapped Validate, not whatever the
    /// builder mutates afterward. Identifiable so we can drive
    /// `.fullScreenCover(item:)` — that pattern guarantees the content closure
    /// only runs when the snapshot exists, avoiding a blank cover caused by
    /// `isPresented:` racing ahead of the snapshot assignment.
    private struct ConfirmationSnapshot: Identifiable {
        let id = UUID()
        let trade: Trade
        let confirmation: TradeConfirmation
        let playersById: [String: Player]
    }

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
            vm.configure(teamsVM: teamsVM, rulesVM: rulesVM, picksVM: picksVM)
            if let initialProposal, vm.trade.movements.isEmpty {
                _ = TradeProposalApplier.apply(initialProposal, to: vm, using: teamsVM)
            } else if !initialTeams.isEmpty && vm.trade.teams.isEmpty {
                vm.setTeams(initialTeams)
            }
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
        .sheet(isPresented: $showingHistory) {
            TradeHistorySheet(vm: vm)
        }
        .sheet(isPresented: $showingDepthChart) {
            DepthChartSheet(vm: vm)
                .environmentObject(teamsVM)
        }
        .sheet(isPresented: $showAdvisor) {
            if let tricode = advisorTeamTricode {
                TradeAdvisorSheet(
                    viewModel: TradeAdvisorViewModel(team: tricode, service: FirebaseAdvisorService()),
                    onApply: { proposal in
                        _ = TradeProposalApplier.apply(proposal, to: vm, using: teamsVM)
                        showAdvisor = false
                    })
                .environmentObject(teamsVM)
            }
        }
        .fullScreenCover(item: $confirmationSnapshot) { snapshot in
            TradeConfirmationView(
                confirmation: snapshot.confirmation,
                trade: snapshot.trade,
                playersById: snapshot.playersById,
                onDismiss: { confirmationSnapshot = nil }
            )
        }
        .onChange(of: vm.validation?.isValid) { _, isValid in
            if isValid == true {
                presentConfirmation()
            }
        }
    }

    private func presentConfirmation() {
        var lookup: [String: Player] = [:]
        for team in vm.trade.teams {
            for p in vm.incomingPlayers(to: team.teamId) { lookup[p.id] = p }
            for p in vm.outgoingPlayers(from: team.teamId) { lookup[p.id] = p }
        }
        let confirmation = TradeConfirmation.build(
            trade: vm.trade, playersById: lookup
        )
        confirmationSnapshot = ConfirmationSnapshot(
            trade: vm.trade,
            confirmation: confirmation,
            playersById: lookup
        )
    }

    private var activeTradeView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "chevron.left")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Toggle("Offseason mode (next season)", isOn: $vm.isOffseason)
                    .font(.caption)
                Spacer()
                Button {
                    showAdvisor = true
                } label: {
                    Label("Ask Advisor", systemImage: "sparkles")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(advisorTeamTricode == nil)

                Button {
                    showingDepthChart = true
                } label: {
                    Label("Depth Chart", systemImage: "square.grid.3x3.fill")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))

            rosterDiffBanner

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

    /// Cross-team roster diff: each team's net OFF/DEF Δσ, side by side,
    /// above the tab bar so you can see who's winning each channel without
    /// switching tabs. Hidden until at least one moving player on any side
    /// carries Rev-2 z fields.
    @ViewBuilder
    private var rosterDiffBanner: some View {
        let rows = vm.trade.teams.map { team -> (Team, Double, Double, Bool) in
            let inP = vm.incomingPlayers(to: team.teamId)
            let outP = vm.outgoingPlayers(from: team.teamId)
            var off = 0.0
            var def = 0.0
            var any = false
            for p in inP {
                if let v = p.latentValue?.thetaZOff { off += v; any = true }
                if let v = p.latentValue?.thetaZDef { def += v; any = true }
            }
            for p in outP {
                if let v = p.latentValue?.thetaZOff { off -= v; any = true }
                if let v = p.latentValue?.thetaZDef { def -= v; any = true }
            }
            return (team, off, def, any)
        }
        if rows.contains(where: { $0.3 }) {
            VStack(spacing: 4) {
                Text("Roster Δσ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { i in
                        let (team, off, def, hasData) = rows[i]
                        rosterDiffCell(team: team, off: off, def: def, hasData: hasData)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }

    private func rosterDiffCell(team: Team, off: Double, def: Double, hasData: Bool) -> some View {
        VStack(spacing: 2) {
            Text(team.teamId)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if hasData {
                HStack(spacing: 6) {
                    sigmaPill("OFF", off)
                    sigmaPill("DEF", def)
                }
            } else {
                Text("—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func sigmaPill(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(String(format: "%+.2f", value))
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(value > 0 ? .green : (value < 0 ? .red : .secondary))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                vm.validate()
            } label: {
                Label("Validate", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            if vm.canRemoveTeam {
                Button(role: .destructive) {
                    vm.removeTeam(effectiveSelection)
                    selectedTeamId = ""
                } label: {
                    Label("Remove Team", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                vm.reset()
                selectedTeamId = ""
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .contextMenu {
                Button {
                    showingHistory = true
                } label: {
                    Label("View History (\(vm.history.count))", systemImage: "clock.arrow.circlepath")
                }
                .disabled(vm.history.isEmpty)
            }
        }
    }

    /// Tricode to seed the Trade Advisor with: the first team currently in the
    /// trade, falling back to the first team in the league roster.
    private var advisorTeamTricode: String? {
        vm.trade.teams.first?.tricode ?? teamsVM.teams.first?.tricode
    }

    private var effectiveSelection: String {
        if vm.trade.teamIds.contains(selectedTeamId) { return selectedTeamId }
        return vm.trade.teams.first?.teamId ?? ""
    }

    private var currentTeam: Team? {
        vm.trade.teams.first { $0.teamId == effectiveSelection }
    }
}
