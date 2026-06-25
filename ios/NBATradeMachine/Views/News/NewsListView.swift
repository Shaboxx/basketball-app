import SwiftUI

/// League-wide news feed tab. Loads on appear, refreshes on pull + on returning
/// to the foreground. States: error (when empty) / loading (when empty) / empty
/// placeholder / the list. Mirrors PlayersListView's refresh wiring.
struct NewsListView: View {
    @StateObject private var vm = NewsFeedViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Group {
                if let err = vm.errorMessage, vm.items.isEmpty {
                    errorView(err)
                } else if vm.isLoading && vm.items.isEmpty {
                    ProgressView().padding(.top, 80)
                } else if vm.items.isEmpty {
                    ContentUnavailableView(
                        "No news yet",
                        systemImage: "newspaper",
                        description: Text("League news will appear here.")
                    )
                } else {
                    List(vm.items) { NewsRow(item: $0) }
                        .listStyle(.plain)
                        .refreshable { await vm.reload() }
                }
            }
            .navigationTitle("News")
        }
        .task {
            await vm.load()
            didLoad = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && didLoad {
                Task { await vm.reload() }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundStyle(.red)
            Text("Couldn't load news").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
