import SwiftUI

struct TradeAdvisorSheet: View {
    @StateObject var viewModel: TradeAdvisorViewModel
    @EnvironmentObject var teamsVM: TeamsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps "Open in Trade Machine" on a proposal.
    let onApply: (AdvisorProposal) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("What do you want? e.g. add a rim protector under $15M",
                          text: $viewModel.goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                Button {
                    Task { await viewModel.ask() }
                } label: {
                    Label("Ask the Advisor", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canAsk)

                content
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Trade Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .idle:
            Text("Describe the move you're after and the Advisor will propose legal trades for \(viewModel.team).")
                .font(.callout).foregroundStyle(.secondary)
        case .loading:
            HStack { Spacer(); ProgressView("Thinking…"); Spacer() }.padding(.top, 24)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                Button("Try again") { Task { await viewModel.ask() } }
            }
        case .loaded(let resp):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !resp.summary.isEmpty {
                        Text(resp.summary).font(.callout)
                    }
                    ForEach(resp.proposals) { proposal in
                        AdvisorProposalCard(
                            proposal: proposal,
                            displayName: { slug in displayName(for: slug) },
                            onApply: onApply)
                    }
                    if resp.proposals.isEmpty {
                        Text("No legal trade matched that goal. Try loosening a constraint.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func displayName(for slug: String) -> String {
        teamsVM.playersByTeamId.values.flatMap { $0 }.first { $0.id == slug }?.name ?? slug
    }
}
