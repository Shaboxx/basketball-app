import SwiftUI

/// League-wide news feed tab. Loads on appear, refreshes on pull + on returning
/// to the foreground. States: error (when empty) / loading (when empty) / empty
/// placeholder / the list. Mirrors PlayersListView's refresh wiring.
struct NewsListView: View {
    @StateObject private var vm = NewsFeedViewModel()
    @EnvironmentObject private var teamsVM: TeamsViewModel
    // Forwarded into the pushed PlayerDetailView: this stack has TWO navigationDestinations,
    // so the pushed view does NOT inherit the stack's environment (same class of crash as the
    // fantasy-team fix) — inject PlayerDetailView's full dependency set explicitly.
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore
    @EnvironmentObject private var footerState: FooterState
    @EnvironmentObject private var gameStripStore: GameStripStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLoad = false
    @Binding var path: NavigationPath   // owned by ContentView so depth survives tab switches (NAV-19)

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let err = vm.errorMessage, vm.items.isEmpty {
                    errorView(err)
                } else if vm.isLoading && vm.items.isEmpty {
                    // Content-shaped placeholder — fills the region so the header/footer don't shift.
                    ScrollView { NewsListSkeleton() }
                } else if vm.items.isEmpty {
                    ContentUnavailableView(
                        "No news yet",
                        systemImage: "newspaper",
                        description: Text("League news will appear here.")
                    )
                } else {
                    List {
                        Section {
                            NewsGameStripView(store: gameStripStore)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
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
                            if vm.displayedItems.isEmpty && !vm.selectedSlugs.isEmpty {
                                Text("No loaded stories mention the selected player\(vm.selectedSlugs.count > 1 ? "s" : "").")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(vm.displayedItems) { NewsRow(item: $0) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .reportsFooterScroll(footerState)
                    .refreshFailureBanner(vm.refreshFailures)
                    .refreshable { await vm.reload() }
                    .task(id: vm.selectedSlugs) {
                        guard vm.displayedItemsEmpty, vm.selectedSlugs.count == 1,
                              let slug = vm.selectedSlugs.first else { return }
                        await vm.fetchPlayerFallback(slug: slug)
                    }
                }
            }
            // No large title — the app header row already reads "News" (avoid the duplicate).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Player.self) {
                PlayerDetailView(player: $0)
                    .environmentObject(teamsVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
            }
            .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
        }
        .task {
            await vm.load()
            didLoad = true
            await gameStripStore.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && didLoad {
                Task { await vm.reload() }
                Task { await gameStripStore.load() }
            }
        }
    }

    private var sortBinding: Binding<NewsSort> {
        Binding(get: { vm.sort }, set: { newSort in Task { await vm.setSort(newSort) } })
    }

    /// Compact "Hot Right Now" portrait strip — display-only in v1.
    private var hotPlayersStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Hot Right Now").foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
            .font(.caption.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.hotPlayers) { p in
                        hotPlayerCell(p)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    /// Single-tap toggles the feed filter (an accent ring shows selection); double-tap
    /// opens the player's profile when the slug resolves to a rostered player, else falls
    /// back to toggling the filter (so a double-tap is never a dead-end).
    private func hotPlayerCell(_ p: HotPlayer) -> some View {
        let selected = vm.isSelected(p.slug)
        let player = teamsVM.player(slug: p.slug)
        return VStack(spacing: 4) {
            HeadshotImage(slug: p.slug, size: 56)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
            Text(p.name).font(.caption2).lineLimit(1)
                .frame(maxWidth: 64)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let player { path.append(player) } else { vm.toggleSelection(p.slug) }
        }
        .onTapGesture(count: 1) {
            vm.toggleSelection(p.slug)
        }
        // VoiceOver: a button whose primary action toggles the news filter (conveyed by
        // .isSelected); opening the profile is a named rotor action. Restores the
        // semantics the removed NavigationLink provided.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(p.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Filters the news feed to this player")
        .accessibilityAction { vm.toggleSelection(p.slug) }
        .accessibilityAction(named: "Open profile") {
            if let player { path.append(player) }
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
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
    }
}
