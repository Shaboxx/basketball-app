import SwiftUI

struct OffseasonHubView: View {
    @ObservedObject var viewModel: OffseasonViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Offseason")
                .task { if case .idle = viewModel.phase { await viewModel.load() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView("Loading offseason…")
        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(.secondary)
                Text("No simulation yet").font(.headline)
                Text("Run the offseason simulator to see results here.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding()
        case .failed(let msg):
            VStack(spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                Button("Try again") { Task { await viewModel.load() } }
            }.padding()
        case .loaded(let summary):
            loaded(summary)
        }
    }

    @ViewBuilder private func loaded(_ s: OffseasonSummary) -> some View {
        List {
            if !s.narrative.isEmpty {
                Section("Summary") { Text(s.narrative).font(.callout) }
            }
            if s.aiRan {
                Section {
                    Label("AI made \(s.aiSummary.accepted) move(s); \(s.aiSummary.rejected) rejected",
                          systemImage: "sparkles").font(.caption)
                }
            }
            Section("Transactions") {
                let feed = orderedFeed(s.transactions)
                if feed.isEmpty { Text("No transactions.").foregroundStyle(.secondary) }
                ForEach(Array(feed.enumerated()), id: \.offset) { _, tx in TransactionRow(txn: tx) }
            }
            Section("Teams") {
                ForEach(s.teamIndex) { entry in
                    NavigationLink {
                        OffseasonTeamDetailView(tricode: entry.tricode, viewModel: viewModel)
                    } label: {
                        HStack {
                            Text(entry.tricode).font(.callout.weight(.semibold))
                            if let tier = entry.capTier {
                                Text(tier).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.nMoves) move\(entry.nMoves == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                NavigationLink("Unsigned FAs & untraded blocks") { OffseasonListsView(summary: s) }
            }
        }
    }

    /// Trades first, then signings — a light "headline" ordering for the overview feed.
    private func orderedFeed(_ txns: [OffseasonTransaction]) -> [OffseasonTransaction] {
        let trades = txns.filter { if case .trade = $0 { return true } else { return false } }
        let fas = txns.filter { if case .fa = $0 { return true } else { return false } }
        return trades + fas
    }
}
