import SwiftUI

struct AdvisorProposalCard: View {
    let proposal: AdvisorProposal
    /// Resolve a slug -> display name when possible (else show the slug).
    let displayName: (String) -> String
    let onApply: (AdvisorProposal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(proposal.label).font(.headline)
                Spacer()
                if proposal.legal {
                    Label("Legal", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                }
            }
            ForEach(proposal.moves) { move in
                Text("\(displayName(move.playerId))  \(move.fromTeam) → \(move.toTeam)")
                    .font(.subheadline)
            }
            if !proposal.rationale.isEmpty {
                Text(proposal.rationale).font(.callout).foregroundStyle(.secondary)
            }
            if !proposal.tradeoffs.isEmpty {
                Text("Trade-offs: \(proposal.tradeoffs)").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                onApply(proposal)
            } label: {
                Label("Open in Trade Machine", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
