import SwiftUI

struct PlayersListView: View {
    @StateObject private var vm = PlayersViewModel()
    @EnvironmentObject var teamsVM: TeamsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.players.isEmpty {
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
                    .refreshable { await vm.reload() }
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
