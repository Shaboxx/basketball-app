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
                            if let when = feed.updatedAt {
                                Text(when, format: .relative(presentation: .named))
                                    .foregroundStyle(feed.isStale ? .orange : .secondary)
                            } else {
                                Text("never").foregroundStyle(.secondary)
                            }
                            if feed.isStale {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("stale")
                            }
                        }
                    }
                } header: {
                    Text("Last updated")
                } footer: {
                    Text(vm.anyStale
                         ? "Some data may be out of date. Background jobs refresh rosters daily and contracts/picks weekly."
                         : "All feeds are current.")
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
