import SwiftUI

struct TradeMachineView: View {
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @EnvironmentObject var picksVM: PicksViewModel
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var appSettings: AppSettings
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
    @State private var pendingProposal: AdvisorProposal?
    @State private var showReplaceConfirm = false
    @State private var confirmationSnapshot: ConfirmationSnapshot?
    @State private var balancePresentation: BalancePresentation?
    /// Full legality breakdown shown when the red status pill is tapped.
    @State private var legalityDetail: String?
    /// Confirms the destructive "Clear trade" action.
    @State private var showResetConfirm = false
    /// A recovered in-progress trade offered for resume on reopen (NAV-01).
    @State private var pendingDraft: TradeDraft?

    private struct BalancePresentation: Identifiable {
        let id = UUID()
        let result: TradeBalancer.BalanceResult
    }

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
        let tradeCode: String?   // shareable reload code (NAV-21)
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
            // Season mode is global now (settings gear); sync the VM at open.
            vm.isOffseason = appSettings.isOffseasonEffective
            if let initialProposal, vm.trade.movements.isEmpty {
                _ = TradeProposalApplier.apply(initialProposal, to: vm, using: teamsVM)
            } else if vm.trade.teams.isEmpty {
                if !initialTeams.isEmpty { vm.setTeams(initialTeams) }
                // A previous in-progress trade survived a dismiss/kill — offer to
                // resume it (non-destructive: the just-seeded teams stay unless
                // the user chooses Resume). NAV-01.
                if let draft = vm.savedDraft, draft.hasWork { pendingDraft = draft }
            }
        }
        .onDisappear { vm.persistDraftIfNeeded() }
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
        .sheet(item: $balancePresentation) { pres in
            BalanceProposalSheet(vm: vm, initial: pres.result, includePicks: true) { applied in
                vm.applyBalance(applied)
                balancePresentation = nil
            }
        }
        .sheet(isPresented: $showAdvisor, onDismiss: {
            if pendingProposal != nil { showReplaceConfirm = true }
        }) {
            if let tricode = advisorTeamTricode {
                TradeAdvisorSheet(
                    viewModel: TradeAdvisorViewModel(team: tricode, service: FirebaseAdvisorService(),
                                                     teamSet: advisorTeamSet),
                    onApply: { proposal in
                        if vm.hasUncommittedWork {
                            pendingProposal = proposal      // onDismiss -> confirm
                            showAdvisor = false
                        } else {
                            _ = TradeProposalApplier.apply(proposal, to: vm, using: teamsVM)
                            showAdvisor = false
                        }
                    })
                .environmentObject(teamsVM)
            }
        }
        .confirmationDialog("Replace your current trade?",
                            isPresented: $showReplaceConfirm,
                            presenting: pendingProposal) { proposal in
            Button("Replace Trade", role: .destructive) {
                _ = TradeProposalApplier.apply(proposal, to: vm, using: teamsVM)
                pendingProposal = nil
            }
            Button("Cancel", role: .cancel) { pendingProposal = nil }
        } message: { _ in
            Text("This clears the trade you've started and loads the Advisor's proposal.")
        }
        .fullScreenCover(item: $confirmationSnapshot) { snapshot in
            TradeConfirmationView(
                confirmation: snapshot.confirmation,
                trade: snapshot.trade,
                playersById: snapshot.playersById,
                tradeCode: snapshot.tradeCode,
                onDismiss: { confirmationSnapshot = nil }
            )
        }
        .alert(
            "Why this trade isn't legal yet",
            isPresented: Binding(
                get: { legalityDetail != nil },
                set: { if !$0 { legalityDetail = nil } }
            ),
            presenting: legalityDetail
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { detail in
            Text(detail)
        }
        .confirmationDialog(
            "Clear this trade?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Trade", role: .destructive) {
                vm.reset()
                selectedTeamId = ""
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("This removes every player, pick, and cash you've added.")
        }
        .confirmationDialog(
            "Resume your in-progress trade?",
            isPresented: Binding(
                get: { pendingDraft != nil },
                set: { if !$0 { pendingDraft = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDraft
        ) { draft in
            Button("Resume previous trade (\(draft.teamCount) team\(draft.teamCount == 1 ? "" : "s"))") {
                vm.restoreDraft(draft)
                pendingDraft = nil
            }
            Button("Start fresh", role: .destructive) {
                vm.clearDraft()
                pendingDraft = nil
            }
        } message: { _ in
            Text("You have an unsaved trade from before. Resume it, or start fresh with your selected teams.")
        }
    }

    private func presentConfirmation() {
        var lookup: [String: Player] = [:]
        for team in vm.trade.teams {
            for p in vm.incomingPlayers(to: team.teamId) { lookup[p.id] = p }
            for p in vm.outgoingPlayers(from: team.teamId) { lookup[p.id] = p }
        }
        let confirmation = TradeConfirmation.build(
            trade: vm.trade,
            playersById: lookup,
            chemistryByTeam: chemistryByTeam()
        )
        confirmationSnapshot = ConfirmationSnapshot(
            trade: vm.trade,
            confirmation: confirmation,
            playersById: lookup,
            // nil (feature dark) → the share bar's Copy-code button hides.
            tradeCode: TradeCodeGate.shouldShow()
                ? TradeCodec.encode(TradeCode(trade: vm.trade, offseason: vm.isOffseason))
                : nil
        )
    }

    /// Post-trade role-chemistry per team, computed from each team's resulting
    /// starters (current roster ± the moving players). Empty when norms aren't
    /// loaded yet — the confirmation tile degrades to "not yet available".
    private func chemistryByTeam() -> [String: LineupChemistryDelta] {
        guard let norms = normsVM.norms else { return [:] }
        var out: [String: LineupChemistryDelta] = [:]
        for team in vm.trade.teams {
            // roster(for:) already excludes outgoing/waived players.
            let base = vm.roster(for: team.teamId)
            let post = base + vm.incomingPlayers(to: team.teamId)
            let pre = base + vm.outgoingPlayers(from: team.teamId)
            if let chem = TradeChemistry.evaluate(preRoster: pre, postRoster: post, norms: norms) {
                out[team.teamId] = chem
            }
        }
        return out
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

                // Visible Undo — was only reachable via a long-press on Clear
                // (NAV-23). Full step-history stays in Clear's context menu.
                Button {
                    vm.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!vm.canUndo)

                Spacer()
                if AppConfig.aiAdvisorEnabled {
                    Button {
                        showAdvisor = true
                    } label: {
                        Label("Ask Advisor", systemImage: "sparkles")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(advisorTeamTricode == nil)
                }

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
                    TeamTradeTabContent(team: team, vm: vm)
                        .padding(.bottom, 8)
                }
            }
            // Pin status + actions so the always-on legality read stays visible
            // while the user scrolls/edits the roster above it.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    statusPill
                    actionButtons
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.bar)
            }
        }
    }

    /// Always-on legality status, pinned above the actions. Empty trade → a
    /// neutral "how to start" hint; legal → green; illegal → red, leading with
    /// the actual blocking reason and tappable for the full breakdown.
    @ViewBuilder
    private var statusPill: some View {
        switch vm.liveStatus {
        case .empty:
            pillShell(tint: Color(.tertiarySystemFill)) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Tap a player on either roster to start building the trade.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
        case .valid:
            pillShell(tint: Color.green.opacity(0.18)) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Trade is legal")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Trade is legal")
        case let .invalid(reason, extra):
            Button {
                legalityDetail = vm.statusDetail(reason: reason)
            } label: {
                pillShell(tint: Color.red.opacity(0.18)) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            // Lead with the actionable reason, not a generic header.
                            Text(reason)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text(extra > 0
                                 ? "+\(extra) more issue\(extra == 1 ? "" : "s") · tap for details"
                                 : "Tap for details")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Not legal: \(reason)")
            .accessibilityHint("Shows all blocking issues")
        }
    }

    /// Shared pill chrome (padding, shape, house 0.18 tint).
    private func pillShell<Content: View>(tint: Color,
                                          @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint))
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
        VStack(spacing: 8) {
            // Primary gets its own full-width row so it dominates and is never
            // adjacent to the destructive Clear.
            Button {
                presentConfirmation()
            } label: {
                Label("Review Trade", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.liveStatus.isValid)

            HStack(spacing: 10) {
                if vm.canBalance {
                    Button {
                        if let r = vm.balanceTrade(includePicks: true) {
                            balancePresentation = BalancePresentation(result: r)
                        }
                    } label: {
                        Label("Balance", systemImage: "scalemass")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                if vm.canRemoveTeam {
                    Button(role: .destructive) {
                        vm.removeTeam(effectiveSelection)
                        selectedTeamId = ""
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    // Confirm only when there's work to lose.
                    if vm.hasUncommittedWork {
                        showResetConfirm = true
                    } else {
                        vm.reset()
                        selectedTeamId = ""
                    }
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
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
    }

    /// Tricode to seed the Trade Advisor with: the first team currently in the
    /// trade, falling back to the first team in the league roster.
    private var advisorTeamTricode: String? {
        vm.trade.teams.first?.tricode ?? teamsVM.teams.first?.tricode
    }

    /// The teams currently in the trade — the advisor's allowed set (constrains when 2+).
    /// Snapshotted into the sheet's view model at open; the @StateObject is recreated per presentation.
    private var advisorTeamSet: [String] { vm.trade.teams.map { $0.tricode } }

    private var effectiveSelection: String {
        if vm.trade.teamIds.contains(selectedTeamId) { return selectedTeamId }
        return vm.trade.teams.first?.teamId ?? ""
    }

    private var currentTeam: Team? {
        vm.trade.teams.first { $0.teamId == effectiveSelection }
    }
}
