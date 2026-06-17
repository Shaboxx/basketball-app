import SwiftUI

struct OffseasonTeamDetailView: View {
    let tricode: String
    @ObservedObject var viewModel: OffseasonViewModel

    var body: some View {
        content
            .navigationTitle(tricode)
            .task { await viewModel.loadTeam(tricode) }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.teamPhase {
        case .idle, .loading:
            ProgressView()
        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                Text("No recorded moves").font(.headline)
            }.padding()
        case .failed(let msg):
            VStack(spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                Button("Try again") { Task { await viewModel.loadTeam(tricode) } }
            }.padding()
        case .loaded(let team):
            loaded(team)
        }
    }

    @ViewBuilder private func loaded(_ team: TeamOffseason) -> some View {
        List {
            if let after = team.capAfter {
                Section("Cap") {
                    capRow("Team salary", team.capBefore?.teamSalary, after.teamSalary)
                    capRow("Cap room", team.capBefore?.capRoom, after.capRoom)
                    if let tier = after.capTier { labelRow("Tier", tier) }
                    if let apron = after.apronStatus { labelRow("Apron", apron) }
                }
            }
            if !team.acquired.isEmpty {
                Section("Acquired") {
                    ForEach(team.acquired, id: \.self) { Text(offseasonDisplayName($0)) }
                }
            }
            if !team.dealt.isEmpty {
                Section("Dealt") {
                    ForEach(team.dealt, id: \.self) { Text(offseasonDisplayName($0)) }
                }
            }
            Section("Moves") {
                if team.transactions.isEmpty { Text("None.").foregroundStyle(.secondary) }
                ForEach(Array(team.transactions.enumerated()), id: \.offset) { _, tx in
                    TransactionRow(txn: tx)
                }
            }
        }
    }

    @ViewBuilder private func capRow(_ label: String, _ before: Int?, _ after: Int?) -> some View {
        HStack {
            Text(label); Spacer()
            Text(dollars(before)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(dollars(after)).fontWeight(.semibold)
        }.font(.callout)
    }
    @ViewBuilder private func labelRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }.font(.callout)
    }
    private func dollars(_ v: Int?) -> String {
        guard let v else { return "—" }
        return "$\(v / 1_000_000)M"
    }
}
