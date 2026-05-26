import SwiftUI

struct TeamTradeTabContent: View {
    let team: Team
    @ObservedObject var vm: TradeMachineViewModel
    @State private var pendingPlayer: Player?
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
                            IncomingRow(player: p, seasonOffset: vm.activeYearOffset) {
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
                if roster.isEmpty {
                    Text("No remaining players.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(roster.enumerated()), id: \.element.id) { idx, p in
                            PlayerSelectionRow(player: p, seasonOffset: vm.activeYearOffset) {
                                pendingPlayer = p
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            if idx < roster.count - 1 { Divider() }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
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
        .confirmationDialog(
            pendingPlayer.map { "Trade \($0.name)?" } ?? "Trade",
            isPresented: Binding(
                get: { pendingPlayer != nil },
                set: { if !$0 { pendingPlayer = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingPlayer
        ) { player in
            ForEach(otherTeams) { other in
                Button("Send to \(other.fullName)") {
                    vm.tradePlayer(player.id, from: team.teamId, to: other.teamId)
                    pendingPlayer = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingPlayer = nil }
        }
        .sheet(isPresented: $showingAddPick) {
            AddPickSheet(fromTeam: team, vm: vm)
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
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
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

struct IncomingRow: View {
    let player: Player
    let seasonOffset: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HeadshotImage(slug: player.slug, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name).font(.subheadline)
                Text("from \(player.teamId) · \(player.position)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.display(player.salary(forSeasonOffset: seasonOffset)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(player.contractYearsRemaining(from: seasonOffset))y left")
                    .font(.caption2).foregroundStyle(.secondary)
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
