import SwiftUI

struct PlayersListView: View {
    @Binding var path: NavigationPath   // owned by ContentView so depth survives tab switches (NAV-19)
    @StateObject private var vm = PlayersViewModel()
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fantasyStore: FantasyValueStore
    // Held to forward into the pushed PlayerDetailView — a `.navigationDestination`
    // destination does not inherit this stack's @EnvironmentObjects (crash class).
    @EnvironmentObject var normsVM: LeagueNormsViewModel

    private var fantasyMode: Bool { AppConfig.fantasyEnabled && appSettings.fantasyModeOn }

    /// Fantasy-mode sort menu (9-Cat is the default; alphabetical is an option).
    enum FantasySortMode: String, CaseIterable, Identifiable {
        case nineCat, eightCat, points, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .nineCat: return "9-Cat"
            case .eightCat: return "8-Cat"
            case .points: return "Points"
            case .name: return "Name"
            }
        }
    }
    @State private var fantasySort: FantasySortMode = .nineCat

    /// The rendered list: NBA mode uses the VM's sort (default Total σ);
    /// fantasy mode re-sorts the filtered set by the chosen fantasy value.
    private var displayed: [Player] {
        guard fantasyMode else { return vm.filtered }
        switch fantasySort {
        case .name:
            return vm.filtered.sorted { $0.name < $1.name }
        case .nineCat:
            return vm.fantasyOrdered(sort: "nineCat", values: fantasyStore.values, format: .nineCat)
        case .eightCat:
            return vm.fantasyOrdered(sort: "eightCat", values: fantasyStore.values, format: .eightCat)
        case .points:
            let pointsFormat: FantasyFormat = appSettings.fantasyFormat.isPoints
                ? appSettings.fantasyFormat : .pointsEspn
            return vm.fantasyOrdered(sort: "points|\(pointsFormat.rawValue)", values: fantasyStore.values, format: pointsFormat)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let err = vm.errorMessage, vm.players.isEmpty {
                    errorView(err)
                } else if (vm.isLoading || teamsVM.isLoading) && vm.players.isEmpty {
                    ProgressView()
                } else {
                    List(displayed) { p in
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
                                trailingValues(p)
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
                        if fantasyMode {
                            Picker("Sort", selection: $fantasySort) {
                                ForEach(FantasySortMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                        } else {
                            Picker("Sort", selection: $vm.sortMode) {
                                ForEach(PlayersViewModel.SortMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                        }
                    } label: {
                        Label("Sort: \(fantasyMode ? fantasySort.label : vm.sortMode.label)",
                              systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
            }
            .navigationDestination(for: Player.self) { p in
                // Pass the current filtered/sorted list so detail shows a
                // next/prev pager for lateral comparison (NAV-04).
                PlayerDetailView(player: p, siblings: vm.filtered)
                    .environmentObject(teamsVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
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

    private func fmtF(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Row trailing block: fantasy-format values in fantasy mode; salary + OFF/DEF
    /// in NBA mode. Extracted so the List row closure stays cheap to type-check.
    @ViewBuilder
    private func trailingValues(_ p: Player) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if fantasyMode {
                if let fv = fantasyStore.value(for: p.slug) {
                    let nine = fmtF(fv.formats.nineCat.value)
                    let eight = fmtF(fv.formats.eightCat.value)
                    let pts = fmtF(FantasyHeaderPoints.entry(fv, format: appSettings.fantasyFormat).value)
                    Text("9C \(nine) · 8C \(eight)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Pts \(pts)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                }
            } else {
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
