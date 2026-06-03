import SwiftUI

struct TeamTradeTabContent: View {
    let team: Team
    @ObservedObject var vm: TradeMachineViewModel
    @State private var resignTarget: Player?
    @State private var showingSignFA = false
    @State private var showingDraft = false
    @State private var cashText: String = ""
    @State private var showingAddPick = false
    @FocusState private var cashFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            capStatusBox
            cashRow

            let incoming = vm.incomingPlayers(to: team.teamId)
            if !incoming.isEmpty {
                section("Incoming to \(team.teamId)") {
                    VStack(spacing: 0) {
                        ForEach(Array(incoming.enumerated()), id: \.element.id) { idx, p in
                            IncomingRow(
                                player: p,
                                receivingTricode: team.tricode,
                                displayedSalary: vm.effectiveSalary(for: p),
                                yearsLeft: vm.resignedContract(for: p.id)?.years
                                    ?? p.contractYearsRemaining(from: vm.activeYearOffset),
                                isResigned: vm.resignedContract(for: p.id) != nil
                            ) {
                                vm.untradePlayer(p.id)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            if idx < incoming.count - 1 { Divider() }
                        }
                    }
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            let incomingPicks = vm.trade.picksIncoming(to: team.teamId)
            if !incomingPicks.isEmpty {
                section("Incoming picks to \(team.teamId)") {
                    VStack(spacing: 0) {
                        ForEach(Array(incomingPicks.enumerated()), id: \.element.id) { idx, mv in
                            PickRow(movement: mv, direction: .incoming) {
                                vm.removePickMovement(mv.id)
                            }
                            if idx < incomingPicks.count - 1 { Divider() }
                        }
                    }
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            section("\(team.teamId) Roster") {
                let roster = vm.roster(for: team.teamId)
                let released = vm.waivedPlayers(for: team.teamId) + vm.dismissedPlayers(for: team.teamId)
                if roster.isEmpty {
                    Text("No remaining players.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(roster.enumerated()), id: \.element.id) { idx, p in
                            rosterRow(p)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                            if idx < roster.count - 1 { Divider() }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }

                if !released.isEmpty {
                    Text("Waived / Released")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(released.enumerated()), id: \.element.id) { idx, p in
                            releasedRow(p)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                            if idx < released.count - 1 { Divider() }
                        }
                    }
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if vm.isOffseason {
                offseasonActions
                signedFreeAgentsBlock
                draftedProspectsBlock
            }

            picksSection

            if !vm.fitWarnings.filter({ $0.receivingTeamId == team.teamId }).isEmpty {
                section("Fit warnings") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.fitWarnings.filter { $0.receivingTeamId == team.teamId }) { w in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                Text("\(w.playerName): \(w.message)").font(.caption)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .sheet(isPresented: $showingAddPick) {
            AddPickSheet(fromTeam: team, vm: vm)
        }
        .sheet(item: $resignTarget) { player in
            ResignContractSheet(player: player, teamId: team.teamId, vm: vm)
        }
        .sheet(isPresented: $showingSignFA) {
            SignFreeAgentSheet(teamId: team.teamId, vm: vm)
        }
        .sheet(isPresented: $showingDraft) {
            DraftPlayerSheet(team: team, vm: vm)
        }
    }

    /// One active-roster row: the tappable player content is wrapped in a
    /// `Menu` (anchors its dropdown directly to the row — fixes the prior
    /// `confirmationDialog` anchoring bug) with a trailing chevron link.
    @ViewBuilder
    private func rosterRow(_ p: Player) -> some View {
        let expired = vm.isExpired(p)
        HStack(spacing: 8) {
            Menu {
                if expired {
                    Button { resignTarget = p } label: {
                        Label("Re-sign…", systemImage: "signature")
                    }
                    Button(role: .destructive) { vm.dismissPlayer(p, from: team.teamId) } label: {
                        Label("Dismiss Player", systemImage: "person.fill.xmark")
                    }
                } else {
                    ForEach(otherTeams) { other in
                        Button("Send to \(other.fullName)") {
                            vm.tradePlayer(p.id, from: team.teamId, to: other.teamId)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { vm.waivePlayer(p, from: team.teamId) } label: {
                        Label("Waive Player", systemImage: "person.fill.xmark")
                    }
                }
            } label: {
                PlayerSelectionRow(
                    player: p,
                    seasonOffset: vm.activeYearOffset,
                    displayedSalary: vm.effectiveSalary(for: p),
                    isExpired: expired
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: p) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// One waived/dismissed row, grayed, with a single undo action.
    @ViewBuilder
    private func releasedRow(_ p: Player) -> some View {
        let waived = vm.isWaived(p.id)
        HStack(spacing: 8) {
            Menu {
                if waived {
                    Button { vm.unwaivePlayer(p.id) } label: {
                        Label("Undo Waive", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button { vm.undismissPlayer(p.id) } label: {
                        Label("Restore Player", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                PlayerSelectionRow(
                    player: p,
                    seasonOffset: vm.activeYearOffset,
                    displayedSalary: vm.effectiveSalary(for: p),
                    isExpired: vm.isExpired(p),
                    isReleased: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: p) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Sign Player" / "Draft Player" buttons surfaced only in offseason
    /// mode. Sit just below the roster so they sit beside the asset that
    /// the user just inspected. The draft button is disabled when the team
    /// owns no upcoming first-round picks.
    private var offseasonActions: some View {
        HStack(spacing: 10) {
            Button {
                showingSignFA = true
            } label: {
                Label("Sign Player", systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingDraft = true
            } label: {
                Label("Draft Player", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var signedFreeAgentsBlock: some View {
        let signed = vm.signedFAs(for: team.teamId)
        if !signed.isEmpty {
            section("Signed free agents") {
                VStack(spacing: 0) {
                    ForEach(Array(signed.enumerated()), id: \.element.id) { idx, fa in
                        SignedFreeAgentRow(fa: fa) {
                            vm.cancelFreeAgent(id: fa.id, from: team.teamId)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        if idx < signed.count - 1 { Divider() }
                    }
                }
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var draftedProspectsBlock: some View {
        let drafted = vm.draftPicks(for: team.teamId)
        if !drafted.isEmpty {
            section("Drafted prospects") {
                VStack(spacing: 0) {
                    ForEach(Array(drafted.enumerated()), id: \.element.id) { idx, p in
                        DraftedProspectRow(prospect: p) {
                            vm.cancelDraft(id: p.id, from: team.teamId)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        if idx < drafted.count - 1 { Divider() }
                    }
                }
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var picksSection: some View {
        let outgoing = vm.trade.picksOutgoing(from: team.teamId)
        return section("Outgoing picks from \(team.teamId)") {
            VStack(spacing: 0) {
                if outgoing.isEmpty {
                    HStack {
                        Text("No picks added.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    ForEach(Array(outgoing.enumerated()), id: \.element.id) { idx, mv in
                        PickRow(movement: mv, direction: .outgoing) {
                            vm.removePickMovement(mv.id)
                        }
                        if idx < outgoing.count - 1 { Divider() }
                    }
                }
                Divider()
                Button {
                    showingAddPick = true
                } label: {
                    Label("Add Pick", systemImage: "plus.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                .disabled(otherTeams.isEmpty)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var otherTeams: [Team] {
        vm.trade.teams.filter { $0.teamId != team.teamId }
    }

    private var cashRow: some View {
        let amount = vm.trade.cash(from: team.teamId)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Cash sent").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $cashText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($cashFocused)
                    .frame(maxWidth: 130)
                Text(amount > 0 ? Money.display(amount) : "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            if amount > Trade.cashLimit {
                Label("Over $8.12M season cash limit", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { syncCashText() }
        .onChange(of: cashFocused) { _, focused in
            if !focused { commitCash() }
        }
        .onChange(of: vm.trade.cash(from: team.teamId)) { _, _ in
            if !cashFocused { syncCashText() }
        }
    }

    private func syncCashText() {
        let amount = vm.trade.cash(from: team.teamId)
        cashText = amount > 0 ? String(amount) : ""
    }

    private func commitCash() {
        let parsed = Int(cashText.filter(\.isNumber)) ?? 0
        vm.setCash(parsed, from: team.teamId)
        syncCashText()
    }

    private var capStatusBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(team.fullName).font(.headline)
                Spacer()
                if let tier = vm.capTier(for: team.teamId) { CapTierBadge(tier: tier) }
            }
            HStack(spacing: 0) {
                summaryStat("Outgoing", vm.outgoingSalary(from: team.teamId))
                summaryStat("Incoming", vm.incomingSalary(to: team.teamId))
                summaryStat("Post-Trade", vm.postTradeTotal(for: team.teamId))
            }
            latentValueDeltaRow
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Live OFF/DEF σ delta for the in-progress trade, mirroring the
    /// post-validation rollup so the user sees the same number while still
    /// assembling the package. Hidden until at least one moving player on
    /// either side has Rev-2 z fields — prevents misleading 0.00 when the
    /// trade is empty or only involves un-rated players.
    @ViewBuilder
    private var latentValueDeltaRow: some View {
        let inP = vm.incomingPlayers(to: team.teamId)
        let outP = vm.outgoingPlayers(from: team.teamId)
        let (off, def, hasData) = sigmaDelta(incoming: inP, outgoing: outP)
        if hasData {
            HStack(spacing: 0) {
                sigmaStat("OFF Δσ", off)
                sigmaStat("DEF Δσ", def)
            }
            .padding(.top, 4)
        }
    }

    private func sigmaStat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.2f", value))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? .green : (value < 0 ? .red : .secondary))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sigmaDelta(
        incoming: [Player], outgoing: [Player]
    ) -> (off: Double, def: Double, hasData: Bool) {
        var off = 0.0
        var def = 0.0
        var any = false
        for p in incoming {
            if let v = p.latentValue?.thetaZOff { off += v; any = true }
            if let v = p.latentValue?.thetaZDef { def += v; any = true }
        }
        for p in outgoing {
            if let v = p.latentValue?.thetaZOff { off -= v; any = true }
            if let v = p.latentValue?.thetaZDef { def -= v; any = true }
        }
        return (off, def, any)
    }

    private func summaryStat(_ label: String, _ amount: Int) -> some View {
        VStack(spacing: 2) {
            Text(Money.display(amount)).font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }
}

struct SignedFreeAgentRow: View {
    let fa: TradeMachineViewModel.SignedFreeAgent
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.square")
                .foregroundStyle(.blue)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(fa.name).font(.subheadline)
                    Text(fa.kind.shortLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.18), in: Capsule())
                }
                Text(fa.position).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.display(fa.salary))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(fa.years)y").font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
    }
}

struct DraftedProspectRow: View {
    let prospect: TradeMachineViewModel.DraftedProspect
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(prospect.name).font(.subheadline)
                Text("\(prospect.position) · Pick #\(prospect.pickOverall) · \(prospect.pickYear)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if prospect.rookieScaleSalary > 0 {
                Text(Money.display(prospect.rookieScaleSalary))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
    }
}

struct IncomingRow: View {
    let player: Player
    /// Tricode of the team RECEIVING this player — used to look up the
    /// team-relative Trade Value tier/tags for the badges.
    let receivingTricode: String
    /// Effective salary for the active year — honors an offseason re-sign
    /// override so a re-signed expired player shows their NEW salary, not $0.
    let displayedSalary: Int
    /// Contract years left for the active year (re-sign years when re-signed).
    let yearsLeft: Int
    /// True when this player carries an in-flight offseason re-sign.
    var isResigned: Bool = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HeadshotImage(slug: player.slug, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(player.name).font(.subheadline)
                    if isResigned {
                        PlayerChip(label: "Re-signed",
                                   background: .green.opacity(0.8), foreground: .black)
                    }
                    if let entry = player.tradeValue?.forTeam(receivingTricode),
                       let tier = entry.tier {
                        TradeTierBadge(tier: tier)
                        EngineChips(tags: player.tradeValue?.tags ?? [])
                    }
                }
                Text("from \(player.teamId) · \(player.position)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.display(displayedSalary))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(yearsLeft)y left")
                    .font(.caption2).foregroundStyle(.secondary)
                if let sigma = incomingRowSigma(player) {
                    Text(sigma)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
            NavigationLink(value: player) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// `OFF +x.xx · DEF +x.xx` line; nil for players without Rev-2 z fields.
    private func incomingRowSigma(_ p: Player) -> String? {
        guard let lv = p.latentValue,
              (lv.thetaZOff != nil || lv.thetaZDef != nil)
        else { return nil }
        let o = lv.thetaZOff.map { String(format: "%+.2f", $0) } ?? "—"
        let d = lv.thetaZDef.map { String(format: "%+.2f", $0) } ?? "—"
        return "OFF \(o) · DEF \(d)"
    }
}

struct PickRow: View {
    enum Direction { case incoming, outgoing }

    let movement: PickMovement
    let direction: Direction
    let onRemove: () -> Void

    private static let referenceYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: direction == .incoming ? "ticket.fill" : "ticket")
                .foregroundStyle(direction == .incoming ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(movement.pick.shortLabel).font(.subheadline)
                Text(direction == .incoming ? "from \(movement.fromTeamId)" : "to \(movement.toTeamId)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var valueText: String {
        let v = PickValuator.value(for: movement.pick, currentYear: Self.referenceYear)
        return String(format: "≈ $%.1fM", v)
    }
}
