import SwiftUI

struct PlayersListView: View {
    @StateObject private var vm = PlayersViewModel()
    @EnvironmentObject var teamsVM: TeamsViewModel

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
                                    if let sigma = sigmaLine(for: p) {
                                        Text(sigma)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
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
        .task { await vm.load() }
    }

    /// One-line σ summary appended to the row — picks the channel matching
    /// the current sort, or shows the joint OFF/DEF pair under name/salary
    /// sorts. Returns nil for players without Rev-2 z fields so the row
    /// degrades cleanly.
    private func sigmaLine(for p: Player) -> String? {
        guard let lv = p.latentValue,
              (lv.thetaZOff != nil || lv.thetaZDef != nil || lv.thetaZ != nil)
        else { return nil }
        switch vm.sortMode {
        case .offSigmaDesc:
            return lv.thetaZOff.map { String(format: "OFF %+.2fσ", $0) }
        case .defSigmaDesc:
            return lv.thetaZDef.map { String(format: "DEF %+.2fσ", $0) }
        case .totalSigmaDesc:
            return lv.thetaZ.map { String(format: "TOT %+.2fσ", $0) }
        case .name, .salaryDesc:
            let o = lv.thetaZOff.map { String(format: "%+.2f", $0) } ?? "—"
            let d = lv.thetaZDef.map { String(format: "%+.2f", $0) } ?? "—"
            return "OFF \(o) · DEF \(d)"
        }
    }
}
