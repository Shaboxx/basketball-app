import SwiftUI

/// Read-only "Data freshness" sheet (reached from the settings gear): when each
/// external feed last refreshed, with a stale badge if a feed is past its cadence.
/// Closes the loop on the server-side dead-man's-switch — the user sees staleness
/// instead of week-old rosters rendered with full confidence.
struct DataHealthView: View {
    @StateObject private var vm = DataHealthViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(vm.feeds) { feed in
                        HStack {
                            Text(feed.label)
                            Spacer()
                            switch feed.state {
                            case .fresh:
                                if let when = feed.updatedAt {
                                    Text(when, format: .relative(presentation: .named))
                                        .foregroundStyle(.secondary)
                                }
                            case .stale:
                                if let when = feed.updatedAt {
                                    Text(when, format: .relative(presentation: .named))
                                        .foregroundStyle(.orange)
                                }
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("stale")
                            case .unknown:
                                // No timestamp / read failed — don't imply staleness.
                                Text("Unknown").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Last updated")
                } footer: {
                    switch vm.status {
                    case .current:
                        Text("All feeds are current. Background jobs refresh rosters daily and contracts/picks weekly.")
                    case .someStale:
                        Text("Some data may be out of date. Background jobs refresh rosters daily and contracts/picks weekly.")
                    case .unavailable:
                        Text("Couldn’t check data freshness right now.")
                    }
                }
            }
            .navigationTitle("Data Freshness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
    }
}
