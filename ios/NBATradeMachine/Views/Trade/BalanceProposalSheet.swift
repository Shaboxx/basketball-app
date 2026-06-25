import SwiftUI

/// Preview of the deterministic balancer's suggestions. Shows before/after
/// legality + value gap, the additions grouped by reason, and a picks toggle
/// that re-runs the balancer. Apply replays the additions onto the trade.
struct BalanceProposalSheet: View {
    @ObservedObject var vm: TradeMachineViewModel
    let onApply: (TradeBalancer.BalanceResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var includePicks: Bool
    @State private var result: TradeBalancer.BalanceResult

    init(vm: TradeMachineViewModel,
         initial: TradeBalancer.BalanceResult,
         includePicks: Bool,
         onApply: @escaping (TradeBalancer.BalanceResult) -> Void) {
        self.vm = vm
        self.onApply = onApply
        _includePicks = State(initialValue: includePicks)
        _result = State(initialValue: initial)
    }

    private var legalAdds: [TradeBalancer.BalanceAddition] {
        result.additions.filter { $0.reason != .fairness }
    }
    private var fairAdds: [TradeBalancer.BalanceAddition] {
        result.additions.filter { $0.reason == .fairness }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { headerView }

                if result.outcome == .alreadyBalanced {
                    Section { Text("This trade is already legal and fair.").foregroundStyle(.secondary) }
                }
                if result.outcome == .couldNotLegalize {
                    Section { Text("Couldn't make this legal from these rosters — the salary gap is too large.")
                        .foregroundStyle(.orange) }
                }
                if result.outcome == .legalizedButGapRemains {
                    Section { Text("Made it legal, but the value gap couldn't be fully closed from these rosters.")
                        .foregroundStyle(.secondary) }
                }

                if !legalAdds.isEmpty {
                    Section("To make it legal") { ForEach(legalAdds.indices, id: \.self) { row(legalAdds[$0]) } }
                }
                if !fairAdds.isEmpty {
                    Section("To even the value") { ForEach(fairAdds.indices, id: \.self) { row(fairAdds[$0]) } }
                }

                Section {
                    Toggle("Include draft picks", isOn: $includePicks)
                }
            }
            .navigationTitle("Balance Trade")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: includePicks) { _, newValue in
                if let r = vm.balanceTrade(includePicks: newValue) { result = r }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(result); dismiss() }
                        .disabled(result.additions.isEmpty)
                }
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Legality").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(result.beforeLegal ? "Legal" : "Illegal").foregroundStyle(result.beforeLegal ? .green : .red)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text(result.afterLegal ? "Legal" : "Illegal").foregroundStyle(result.afterLegal ? .green : .red)
            }
            HStack {
                Text("Value gap").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Money.display(Int(abs(result.beforeGap)))).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text(Money.display(Int(abs(result.afterGap)))).foregroundStyle(.primary)
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    private func row(_ add: TradeBalancer.BalanceAddition) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(add.move.candidate.label).font(.subheadline.weight(.semibold))
                Text(add.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("→ \(receiverName(add.move.toTeamId))").font(.caption2).foregroundStyle(.secondary)
                if add.move.candidate.salary > 0 {
                    Text(Money.display(add.move.candidate.salary)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func receiverName(_ teamId: String) -> String {
        vm.trade.teams.first { $0.teamId == teamId }?.tricode ?? teamId
    }
}
