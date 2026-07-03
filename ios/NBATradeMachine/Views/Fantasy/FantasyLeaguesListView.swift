import SwiftUI

/// Fantasy-mode Leagues surface: a New League row + a list of saved leagues (name +
/// still-existing member count). Swipe: Delete / Rename. Mirrors `FantasyTeamsListView`
/// (its own NavigationStack, a BuilderTarget wrapper, a rename `.alert`, and sheet env
/// re-injection since SwiftUI does not always propagate env objects into a `.sheet`).
/// Rendered inside `FantasyHomeView`'s Leagues tab (which owns no NavigationStack).
struct FantasyLeaguesListView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyDraftStore: FantasyDraftStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @EnvironmentObject var teamsVM: TeamsViewModel

    @State private var path = NavigationPath()
    @State private var builderLeague: BuilderTarget?
    @State private var renameTarget: FantasyLeague?
    @State private var renameText: String = ""
    @State private var deleteTarget: FantasyLeague?
    @State private var showImport = false

    /// Identifiable wrapper so `.sheet(item:)` builds the builder once a league exists.
    private struct BuilderTarget: Identifiable { let id: UUID }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        let id = fantasyLeagueStore.createLeague(name: "New League")
                        builderLeague = BuilderTarget(id: id)
                    } label: {
                        Label("New League", systemImage: "plus.circle")
                    }
                    if AppConfig.leagueImportEnabled {
                        Button {
                            showImport = true
                        } label: {
                            Label("Import League", systemImage: "arrow.down.circle")
                        }
                    }
                }

                if fantasyLeagueStore.leagues.isEmpty {
                    Section {
                        Text("No leagues yet — tap New League to build one.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your Leagues") {
                        ForEach(fantasyLeagueStore.leagues) { league in
                            NavigationLink(value: league) {
                                leagueRow(league)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTarget = league
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .confirmationDialog("Are you sure you want to delete the league?",
                                                isPresented: Binding(get: { deleteTarget?.id == league.id },
                                                                     set: { if !$0 { deleteTarget = nil } }),
                                                titleVisibility: .visible) {
                                Button("Delete League", role: .destructive) {
                                    if let l = deleteTarget {
                                        fantasyDraftStore.resetDraft(leagueId: l.id)   // purge its draft blob
                                        fantasyTradeStore.removeTrades(for: l.id)      // purge its trade blobs
                                        fantasyLeagueStore.delete(l.id)
                                    }
                                    deleteTarget = nil
                                }
                                Button("Cancel", role: .cancel) { deleteTarget = nil }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    renameTarget = league
                                    renameText = league.name
                                } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Leagues")
            .navigationDestination(for: FantasyLeague.self) { league in
                FantasyLeagueDetailView(leagueId: league.id)
            }
        }
        .sheet(item: $builderLeague) { target in
            FantasyLeagueBuilderView(leagueId: target.id)
                .environmentObject(fantasyLeagueStore)
                .environmentObject(fantasyTeamStore)
                .environmentObject(fantasyDraftStore)
                .environmentObject(fantasyTradeStore)
        }
        .sheet(isPresented: $showImport) {
            FantasyLeagueImportView(leagueStore: fantasyLeagueStore, teamStore: fantasyTeamStore) { newId in
                if let league = fantasyLeagueStore.league(newId) { path.append(league) }
            }
            .environmentObject(teamsVM)
        }
        .alert("Rename League", isPresented: renameBinding) {
            TextField("League name", text: $renameText)
            Button("Save") {
                if let l = renameTarget, !FantasyNameRules.readsProfane(renameText) {
                    fantasyLeagueStore.rename(l.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Names with profanity are rejected.")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    @ViewBuilder
    private func leagueRow(_ league: FantasyLeague) -> some View {
        let count = league.teamIds.filter { fantasyTeamStore.team($0) != nil }.count
        VStack(alignment: .leading, spacing: 2) {
            Text(league.name).font(.subheadline.bold())
            Text("\(count) team\(count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
