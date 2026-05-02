import SwiftUI

struct TeamTradeTabContent: View {
    let team: Team
    @ObservedObject var vm: TradeMachineViewModel
    @State private var pendingPlayer: Player?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            capStatusBox

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
    }

    private var otherTeams: [Team] {
        vm.trade.teams.filter { $0.teamId != team.teamId }
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
