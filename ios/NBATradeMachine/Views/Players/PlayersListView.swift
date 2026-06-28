import SwiftUI

struct PlayersListView: View {
    @StateObject private var vm = PlayersViewModel()
    @EnvironmentObject var teamsVM: TeamsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let err = vm.errorMessage, vm.players.isEmpty {
                    errorView(err)
                } else if (vm.isLoading || teamsVM.isLoading) && vm.players.isEmpty {
                    ProgressView()
                } else {
                    List(vm.filtered) { p in
                        NavigationLink(value: p) {
                            HStack(spacing: 12) {
                                HeadshotImage(slug: p.slug, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.subheadline.bold())
                                    HStack(spacing: 6) {
                                        Text(p.teamId).font(.caption).foregroundStyle(.secondary)
                                        Text("·").foregroundStyle(.secondary)
                                        Text(p.position).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Money.display(p.currentSalary))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if let valueLine = valueLine(for: p) {
                                        Text(valueLine)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await teamsVM.reload()                  // refresh the shared source
                        vm.adopt(teamsVM.allRosteredPlayers)
                    }
                }
            }
            .navigationTitle("Players")
            .searchable(text: $vm.searchText, prompt: "Search players")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $vm.sortMode) {
                            ForEach(PlayersViewModel.SortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Label("Sort: \(vm.sortMode.label)",
                              systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
            }
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
            }
        }
        // Derive from TeamsViewModel's single shared fetch (no second whole-collection
        // read). teamsVM.load() is idempotent; adopt once it's available and re-adopt
        // whenever the shared data reloads (incl. ContentView's throttled foreground
        // refresh) — so this view no longer needs its own scenePhase handler.
        .task {
            await teamsVM.load()
            vm.adopt(teamsVM.allRosteredPlayers)
        }
        .onChange(of: teamsVM.dataVersion) { _, _ in
            vm.adopt(teamsVM.allRosteredPlayers)
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundStyle(.red)
            Text("Couldn't load players").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Try Again") { Task { await vm.reload() } }
                .buttonStyle(.borderedProminent)
        }.padding()
    }

    /// One-line value summary appended to the row — picks the channel matching
    /// the current sort, or shows the joint OFF/DEF pair under name/salary
    /// sorts. Returns nil for players without a display value so the row
    /// degrades cleanly.
    private func valueLine(for p: Player) -> String? {
        guard p.hasDisplayValue else { return nil }
        switch vm.sortMode {
        case .offSigmaDesc:
            return p.dispOff.map { "OFF \(Player.fmtVal($0))" }
        case .defSigmaDesc:
            return p.dispDef.map { "DEF \(Player.fmtVal($0))" }
        case .totalSigmaDesc:
            return p.dispTotal.map { "TOT \(Player.fmtVal($0))" }
        case .name, .salaryDesc:
            return "OFF \(Player.fmtVal(p.dispOff)) · DEF \(Player.fmtVal(p.dispDef))"
        }
    }
}
