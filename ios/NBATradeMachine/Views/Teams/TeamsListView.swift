import SwiftUI

struct TeamsListView: View {
    // Sort/filter now lives (memoized) in TeamsViewModel; alias keeps the @AppStorage + Picker terse.
    private typealias SortMode = TeamsViewModel.SortMode

    @EnvironmentObject var teamsVM: TeamsViewModel
    // Forwarded into the pushed TeamDetailView: a `.navigationDestination` destination
    // does not reliably inherit this stack's @EnvironmentObjects (same crash class as
    // the fantasy-team fix), so each is injected explicitly at the destination.
    @EnvironmentObject var rulesVM: LeagueRulesViewModel
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var footerState: FooterState
    @EnvironmentObject var searchState: SearchState

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

    /// Value channel the grade badge reflects, so its number is monotonic with the sort.
    private var teamChannel: TeamsViewModel.ValueChannel {
        switch sortMode {
        case .offSigmaDesc: return .off
        case .defSigmaDesc: return .def
        default:            return .total
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if let err = teamsVM.errorMessage, teamsVM.teams.isEmpty {   // full-screen error only when empty
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                        Text("Couldn't load teams").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await teamsVM.reload() } }
                            .buttonStyle(.borderedProminent)
                    }.padding().padding(.top, 60)
                } else if teamsVM.isLoading && teamsVM.teams.isEmpty {
                    TeamGridSkeleton()   // content-shaped placeholder instead of a bare spinner
                } else if teamsVM.teams.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Teams unavailable").font(.headline)
                        Text("Pull to refresh, or try again in a moment.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await teamsVM.reload() } }
                            .buttonStyle(.borderedProminent)
                    }.padding().padding(.top, 60)
                } else if teamsVM.displayedTeams(sort: sortMode, query: searchState.text).isEmpty
                            && !searchState.text.isEmpty {
                    // Teams loaded, but the search matches nothing — distinguish "no matches" from
                    // the unavailable/error states (mirrors the Players tab) instead of a blank grid.
                    ContentUnavailableView.search(text: searchState.text)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(teamsVM.displayedTeams(sort: sortMode, query: searchState.text)) { team in
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
            .reportsFooterScroll(footerState)
            .refreshFailureBanner(teamsVM.refreshFailures)
            .navigationTitle("")   // app header row already reads "Teams" (avoid the duplicate)
            .navigationBarTitleDisplayMode(.inline)
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
                    .environmentObject(teamsVM)
                    .environmentObject(rulesVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
            }
            // Registered at the stack ROOT (not inside the pushed TeamDetailView) so the
            // destination exists before any push — a child-declared destination could miss
            // the first player tap (caution-triangle placeholder) and triggered the
            // "declared earlier on the stack" duplicate warnings.
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
                    .environmentObject(teamsVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
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
            if let grade = teamsVM.teamGrade(for: team.teamId, channel: teamChannel) {
                ValueGradeBadge(grade: grade, caption: teamChannel.label)   // OFF/DEF σ lives on the team detail
            } else if rollup.rated > 0 {
                Text("OFF \(Player.fmtVal(rollup.off)) · DEF \(Player.fmtVal(rollup.def))")
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
}
