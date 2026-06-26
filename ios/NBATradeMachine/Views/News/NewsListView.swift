import SwiftUI

/// League-wide news feed tab. Loads on appear, refreshes on pull + on returning
/// to the foreground. States: error (when empty) / loading (when empty) / empty
/// placeholder / the list. Mirrors PlayersListView's refresh wiring.
struct NewsListView: View {
    @StateObject private var vm = NewsFeedViewModel()
    @EnvironmentObject private var teamsVM: TeamsViewModel
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
                    List {
                        if !vm.hotPlayers.isEmpty {
                            Section {
                                hotPlayersStrip
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                            }
                        }
                        Section {
                            Picker("Sort", selection: sortBinding) {
                                ForEach(NewsSort.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowSeparator(.hidden)
                        }
                        Section {
                            ForEach(vm.items) { NewsRow(item: $0) }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.reload() }
                }
            }
            .navigationTitle("News")
            .navigationDestination(for: Player.self) { PlayerDetailView(player: $0) }
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

    private var sortBinding: Binding<NewsSort> {
        Binding(get: { vm.sort }, set: { newSort in Task { await vm.setSort(newSort) } })
    }

    /// Compact "Hot Right Now" portrait strip — display-only in v1.
    private var hotPlayersStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔥 Hot Right Now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.hotPlayers) { p in
                        // Tappable -> player detail when the slug resolves to a
                        // rostered player; otherwise a plain (display-only) cell.
                        if let player = teamsVM.player(slug: p.slug) {
                            NavigationLink(value: player) { hotPlayerCell(p) }
                                .buttonStyle(.plain)
                        } else {
                            hotPlayerCell(p)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    private func hotPlayerCell(_ p: HotPlayer) -> some View {
        VStack(spacing: 4) {
            HeadshotImage(slug: p.slug, size: 56).clipShape(Circle())
            Text(p.name).font(.caption2).lineLimit(1)
                .frame(maxWidth: 64)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundStyle(.red)
            Text("Couldn't load news").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await vm.reload() } }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding()
    }
}
