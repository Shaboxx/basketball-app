import SwiftUI

struct AddPickSheet: View {
    let fromTeam: Team
    @ObservedObject var vm: TradeMachineViewModel
    @EnvironmentObject var picksVM: PicksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPickId: UUID?
    @State private var destinationTeamId: String
    @State private var conditionType: PickConditionType = .unprotected
    @State private var topXValue: Int = 4
    @State private var partnerTeamId: String = ""

    init(fromTeam: Team, vm: TradeMachineViewModel) {
        self.fromTeam = fromTeam
        self.vm = vm
        let firstOther = vm.trade.teams.first { $0.teamId != fromTeam.teamId }
        _destinationTeamId = State(initialValue: firstOther?.teamId ?? "")
        _partnerTeamId = State(initialValue: firstOther?.teamId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pick to send") {
                    if availablePicks.isEmpty {
                        Text(emptyMessage)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Pick", selection: $selectedPickId) {
                            ForEach(availablePicks) { pick in
                                Text(pick.shortLabel).tag(Optional(pick.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if let pick = selectedPick, let raw = pick.rawDescription {
                    Section("Original detail") {
                        Text(raw).font(.caption).foregroundStyle(.secondary)
                    }
                }
                conditionSection
                Section("Send to") {
                    if otherTeams.isEmpty {
                        Text("Add another team to the trade first.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Destination", selection: $destinationTeamId) {
                            ForEach(otherTeams) { team in
                                Text(team.fullName).tag(team.teamId)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("\(fromTeam.teamId) sends a pick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard let basePick = selectedPick else { return }
                        let modified = applyCondition(to: basePick)
                        vm.addPickMovement(modified, from: fromTeam.teamId, to: destinationTeamId)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                if selectedPickId == nil { selectedPickId = availablePicks.first?.id }
                if !otherTeams.contains(where: { $0.teamId == partnerTeamId }) {
                    partnerTeamId = otherTeams.first?.teamId ?? ""
                }
            }
        }
    }

    @ViewBuilder
    private var conditionSection: some View {
        Section("Condition") {
            Picker("Type", selection: $conditionType) {
                ForEach(PickConditionType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.menu)

            switch conditionType {
            case .unprotected:
                EmptyView()
            case .topXProtected:
                Picker("Protect through", selection: $topXValue) {
                    ForEach(Self.topXOptions, id: \.self) { x in
                        Text(Self.topXLabel(x)).tag(x)
                    }
                }
                .pickerStyle(.menu)
            case .swap, .bestOf, .worstOf:
                if partnerOptions.isEmpty {
                    Text("Add another team to the trade to set a partner.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("With", selection: $partnerTeamId) {
                        ForEach(partnerOptions) { team in
                            Text(team.fullName).tag(team.teamId)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func applyCondition(to pick: Pick) -> Pick {
        switch conditionType {
        case .unprotected:
            return pick
        case .topXProtected:
            return Pick(
                originatingTeamId: pick.originatingTeamId,
                year: pick.year,
                round: pick.round,
                protection: Self.protectionForTopX(topXValue),
                projectedPosition: pick.projectedPosition,
                candidateSources: pick.candidateSources,
                selectionRule: pick.selectionRule,
                isSwap: pick.isSwap,
                rawDescription: pick.rawDescription
            )
        case .swap:
            return Pick(
                originatingTeamId: pick.originatingTeamId,
                year: pick.year,
                round: pick.round,
                protection: pick.protection,
                projectedPosition: pick.projectedPosition,
                candidateSources: pick.candidateSources,
                selectionRule: pick.selectionRule,
                isSwap: true,
                rawDescription: pick.rawDescription
            )
        case .bestOf, .worstOf:
            let rule: PickSelectionRule = conditionType == .bestOf ? .mostFavorable : .leastFavorable
            let sources = Array(Set([pick.originatingTeamId, partnerTeamId])).sorted()
            return Pick(
                originatingTeamId: sources.first ?? pick.originatingTeamId,
                year: pick.year,
                round: pick.round,
                protection: pick.protection,
                projectedPosition: pick.projectedPosition,
                candidateSources: sources,
                selectionRule: rule,
                isSwap: pick.isSwap,
                rawDescription: pick.rawDescription
            )
        }
    }

    private var canSubmit: Bool {
        guard selectedPick != nil, !destinationTeamId.isEmpty else { return false }
        switch conditionType {
        case .swap, .bestOf, .worstOf: return !partnerTeamId.isEmpty
        default: return true
        }
    }

    private var availablePicks: [Pick] {
        let alreadyMoving = Set(
            vm.trade.picksOutgoing(from: fromTeam.teamId).map { Self.matchKey($0.pick) }
        )
        return picksVM.picks(for: fromTeam.teamId).filter {
            !alreadyMoving.contains(Self.matchKey($0))
        }
    }

    private var selectedPick: Pick? {
        guard let id = selectedPickId else { return nil }
        return availablePicks.first { $0.id == id }
    }

    private var emptyMessage: String {
        if picksVM.isLoading { return "Loading picks…" }
        if picksVM.picks(for: fromTeam.teamId).isEmpty { return "No pick data for \(fromTeam.teamId)." }
        return "All of \(fromTeam.teamId)'s picks are already in this trade."
    }

    private var otherTeams: [Team] {
        vm.trade.teams.filter { $0.teamId != fromTeam.teamId }
    }

    private var partnerOptions: [Team] { otherTeams }

    private static let topXOptions = [1, 4, 10, 14]

    private static func topXLabel(_ x: Int) -> String {
        x == 14 ? "Top-14 (Lottery)" : "Top-\(x)"
    }

    private static func protectionForTopX(_ x: Int) -> PickProtection {
        switch x {
        case 4: return .top4Protected
        case 10: return .top10Protected
        case 14: return .lotteryProtected
        default: return .other("Top-\(x) prot.")
        }
    }

    nonisolated private static func matchKey(_ p: Pick) -> String {
        "\(p.originatingTeamId)|\(p.year)|\(p.round)|\(p.protection.rawId)|\(p.candidateSources?.joined(separator: ",") ?? "")|\(p.selectionRule?.rawValue ?? "")|\(p.isSwap)"
    }
}

enum PickConditionType: String, CaseIterable, Identifiable, Hashable {
    case unprotected
    case topXProtected
    case swap
    case bestOf
    case worstOf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unprotected: return "Unprotected"
        case .topXProtected: return "Pick Protection (Top-X)"
        case .swap: return "Swap with team"
        case .bestOf: return "Best of own + team"
        case .worstOf: return "Worst of own + team"
        }
    }
}
