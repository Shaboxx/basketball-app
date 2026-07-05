import SwiftUI

struct TeamsListView: View {
    enum SortMode: String, CaseIterable, Identifiable {
        case name
        case totalSigmaDesc
        case offSigmaDesc
        case defSigmaDesc

        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Name"
            case .totalSigmaDesc: return "Total σ"
            case .offSigmaDesc: return "OFF σ"
            case .defSigmaDesc: return "DEF σ"
            }
        }
    }

    @EnvironmentObject var teamsVM: TeamsViewModel

    /// Selection mode shared with `ContentView`. When `selection.isSelecting`
    /// tiles toggle membership instead of navigating to a team's detail.
    @ObservedObject var selection: TradeSelectionState
    /// Navigation path owned by `ContentView` so it can detect "at root"
    /// (`path.isEmpty`) and pop back to the grid.
    @Binding var path: NavigationPath
    /// Surfaces a `.rejectedMax` toggle so `ContentView` can show the
    /// "6 or less teams" alert.
    var onMaxTeamsReached: () -> Void = {}

    // Remember the user's sort across tab switches / launches (NAV-05).
    @AppStorage("teamsSortMode") private var sortMode: SortMode = .name

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let err = teamsVM.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                        Text("Couldn't load teams").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await teamsVM.reload() } }
                            .buttonStyle(.borderedProminent)
                    }.padding().padding(.top, 60)
                } else if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    ProgressView("Loading teams…").padding(.top, 80)
                } else if teamsVM.teams.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Teams unavailable").font(.headline)
                        Text("Pull to refresh, or try again in a moment.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await teamsVM.reload() } }
                            .buttonStyle(.borderedProminent)
                    }.padding().padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedTeams) { team in
                            if selection.isSelecting {
                                Button {
                                    if selection.toggle(team.teamId) == .rejectedMax {
                                        onMaxTeamsReached()
                                    }
                                } label: {
                                    teamTile(team)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: team) {
                                    teamTile(team)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .refreshable { await teamsVM.reload() }
            .navigationTitle("Teams")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Label("Sort: \(sortMode.label)",
                              systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
            }
            .navigationDestination(for: Team.self) { team in
                TeamDetailView(team: team)
            }
        }
        .task { await teamsVM.load() }
    }

    @ViewBuilder
    private func teamTile(_ team: Team) -> some View {
        let rollup = teamsVM.latentValueRollup(for: team.teamId)
        let isSelected = selection.isSelecting && selection.isSelected(team.teamId)
        VStack(spacing: 6) {
            TeamLogoMark(teamId: team.teamId, size: 56, aliasFont: .caption2)
            Text(team.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(team.city)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if rollup.rated > 0 {
                VStack(spacing: 1) {
                    Text("OFF \(Player.fmtVal(rollup.off))")
                    Text("DEF \(Player.fmtVal(rollup.def))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .green)
                    .padding(4)
            }
        }
    }

    /// Apply the chosen sort. Un-rated teams (no roster has Rev-2 z fields)
    /// fall to the bottom on σ-desc sorts via a -inf sentinel.
    private var sortedTeams: [Team] {
        let teams = teamsVM.teams
        let channel: SortChannel
        switch sortMode {
        case .name:
            return teams.sorted { $0.fullName < $1.fullName }
        case .totalSigmaDesc: channel = .total
        case .offSigmaDesc:   channel = .off
        case .defSigmaDesc:   channel = .def
        }
        // Schwartzian: compute each team's sort key ONCE (sortKey loops the roster
        // via latentValueRollup), then sort by the precomputed key — instead of
        // recomputing the rollup inside every O(n log n) comparison.
        return teams.map { ($0, sortKey($0, channel)) }
                    .sorted { $0.1 > $1.1 }
                    .map(\.0)
    }

    private enum SortChannel { case off, def, total }

    private func sortKey(_ team: Team, _ channel: SortChannel) -> Double {
        let r = teamsVM.latentValueRollup(for: team.teamId)
        guard r.rated > 0 else { return -Double.infinity }
        switch channel {
        case .off: return r.off
        case .def: return r.def
        case .total: return r.off + r.def
        }
    }
}
