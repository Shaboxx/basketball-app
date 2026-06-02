import SwiftUI

/// Post-trade depth chart for every team in the active trade. Each column
/// is a position bucket (PG / SG / SF / PF / C), each row is a player
/// sorted by latent-value theta (falling back to salary). Includes
/// roster players that stay, incoming traded players, signed free agents,
/// and drafted prospects so the chart matches the cap math the rest of
/// the screen shows.
struct DepthChartSheet: View {
    @ObservedObject var vm: TradeMachineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamId: String = ""

    private static let positions: [String] = ["PG", "SG", "SF", "PF", "C"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.trade.teams.isEmpty {
                    Text("Add teams to a trade to see depth charts.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    teamPicker
                    Divider()
                    if let team = currentTeam {
                        ScrollView {
                            DepthChartGrid(
                                positions: Self.positions,
                                entries: entries(for: team)
                            )
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Depth chart")
            .navigationBarTitleDisplayMode(.inline)
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

    /// Builds the post-trade entry list for a team, then buckets it by
    /// position. Salary is the effective salary (so re-sign overrides
    /// flow through) and FA/draft entries get synthesized rows.
    private func entries(for team: Team) -> [String: [DepthEntry]] {
        var entries: [DepthEntry] = []
        for p in vm.roster(for: team.teamId) {
            entries.append(DepthEntry(player: p, salary: vm.effectiveSalary(for: p)))
        }
        for p in vm.incomingPlayers(to: team.teamId) {
            entries.append(DepthEntry(player: p, salary: vm.effectiveSalary(for: p)))
        }
        for fa in vm.signedFAs(for: team.teamId) {
            entries.append(DepthEntry(
                synthetic: .freeAgent(fa),
                name: fa.name,
                position: fa.position,
                salary: fa.salary
            ))
        }
        for prospect in vm.draftPicks(for: team.teamId) {
            entries.append(DepthEntry(
                synthetic: .prospect(prospect),
                name: prospect.name,
                position: prospect.position,
                salary: prospect.rookieScaleSalary
            ))
        }
        return Dictionary(grouping: entries, by: { Self.primaryPosition($0.position) })
    }

    /// Coarse normalization: take the first slash-or-dash-separated token,
    /// uppercase, map G → PG (we don't have side info), F → SF.
    private static func primaryPosition(_ raw: String) -> String {
        let token = raw
            .split(whereSeparator: { "-/ ".contains($0) })
            .first
            .map(String.init)?.uppercased() ?? "?"
        switch token {
        case "PG", "SG", "SF", "PF", "C": return token
        case "G": return "PG"
        case "F": return "SF"
        case "F-C": return "PF"
        default: return token
        }
    }
}

/// One depth chart row. Either a `Player` (with sigma sorting), or a
/// synthetic entry for FA signings / drafted prospects (sorted only by
/// salary).
struct DepthEntry: Identifiable, Hashable {
    enum Synthetic: Hashable {
        case freeAgent(TradeMachineViewModel.SignedFreeAgent)
        case prospect(TradeMachineViewModel.DraftedProspect)
    }

    let id: String
    let player: Player?
    let synthetic: Synthetic?
    let name: String
    let position: String
    let salary: Int

    init(player: Player, salary: Int) {
        self.id = player.id
        self.player = player
        self.synthetic = nil
        self.name = player.name
        self.position = player.position
        self.salary = salary
    }

    init(synthetic: Synthetic, name: String, position: String, salary: Int) {
        switch synthetic {
        case .freeAgent(let fa): self.id = "fa-\(fa.id)"
        case .prospect(let p): self.id = "draft-\(p.id)"
        }
        self.player = nil
        self.synthetic = synthetic
        self.name = name
        self.position = position
        self.salary = salary
    }

    /// Sort key used by the depth chart column. Players use their best
    /// channel theta-z; synthetic entries fall back to salary so they
    /// land near the bottom of the column when unrated.
    var rank: Double {
        if let lv = player?.latentValue {
            let off = lv.thetaZOff ?? -.infinity
            let def = lv.thetaZDef ?? -.infinity
            return max(off, def)
        }
        return -Double(Int.max - salary) / 1_000_000  // crude tiebreaker
    }
}

private struct DepthChartGrid: View {
    let positions: [String]
    let entries: [String: [DepthEntry]]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(positions, id: \.self) { pos in
                    Text(pos)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(positions, id: \.self) { pos in
                    VStack(spacing: 4) {
                        let column = (entries[pos] ?? []).sorted { $0.rank > $1.rank }
                        if column.isEmpty {
                            Text("—")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(column) { entry in
                                DepthChartCell(entry: entry)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.top, 6)
        }
    }
}

private struct DepthChartCell: View {
    let entry: DepthEntry

    var body: some View {
        VStack(spacing: 2) {
            Text(entry.name)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let sigma = sigmaLabel {
                Text(sigma).font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(Money.display(entry.salary))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            if let tag = tagLabel {
                Text(tag)
                    .font(.system(size: 8).bold())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(tagColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(tagColor)
            }
        }
        .padding(6)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var sigmaLabel: String? {
        guard let lv = entry.player?.latentValue else { return nil }
        let o = lv.thetaZOff.map { String(format: "%+.1f", $0) } ?? "—"
        let d = lv.thetaZDef.map { String(format: "%+.1f", $0) } ?? "—"
        return "O\(o) D\(d)"
    }

    private var tagLabel: String? {
        switch entry.synthetic {
        case .freeAgent(let fa): return fa.kind.shortLabel
        case .prospect: return "ROOK"
        case .none: return nil
        }
    }

    private var tagColor: Color {
        switch entry.synthetic {
        case .freeAgent: return .blue
        case .prospect: return .purple
        case .none: return .secondary
        }
    }
}
