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
    @State private var sortMode: SortMode = .name

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let err = teamsVM.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                        Text("Couldn't load teams").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    ProgressView().padding(.top, 80)
                } else if teamsVM.teams.isEmpty {
                    Text("No teams loaded yet — check Xcode console.")
                        .foregroundStyle(.secondary).padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedTeams) { team in
                            NavigationLink(value: team) {
                                teamTile(team)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
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
    }

    /// Apply the chosen sort. Un-rated teams (no roster has Rev-2 z fields)
    /// fall to the bottom on σ-desc sorts via a -inf sentinel.
    private var sortedTeams: [Team] {
        let teams = teamsVM.teams
        switch sortMode {
        case .name:
            return teams.sorted { $0.fullName < $1.fullName }
        case .totalSigmaDesc:
            return teams.sorted {
                sortKey($0, .total) > sortKey($1, .total)
            }
        case .offSigmaDesc:
            return teams.sorted {
                sortKey($0, .off) > sortKey($1, .off)
            }
        case .defSigmaDesc:
            return teams.sorted {
                sortKey($0, .def) > sortKey($1, .def)
            }
        }
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
