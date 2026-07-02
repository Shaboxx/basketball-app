import SwiftUI

/// Fantasy-mode Teams surface: a New Team row + a list of saved fantasy teams
/// (name, player count, "My Team" badge). Swipe: Delete / Set as My Team / Rename.
/// Replaces the NBA team grid when Fantasy mode is on.
struct FantasyTeamsListView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var appSettings: AppSettings

    @State private var path = NavigationPath()
    @State private var builderTeam: BuilderTarget?
    @State private var renameTarget: FantasyTeam?
    @State private var renameText: String = ""

    /// Identifiable wrapper so `.sheet(item:)` builds the builder once a team exists.
    private struct BuilderTarget: Identifiable {
        let id: UUID
        let name: String
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        let id = fantasyTeamStore.createTeam(name: "My Team")
                        builderTeam = BuilderTarget(id: id, name: fantasyTeamStore.team(id)?.name ?? "My Team")
                    } label: {
                        Label("New Team", systemImage: "plus.circle")
                    }
                }

                if fantasyTeamStore.teams.isEmpty {
                    Section {
                        Text("No fantasy teams yet — tap New Team to build one.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Your Fantasy Teams") {
                        ForEach(fantasyTeamStore.teams) { team in
                            NavigationLink(value: team) {
                                teamRow(team)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    fantasyTeamStore.delete(team.id)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    fantasyTeamStore.setMyTeam(team.id)
                                } label: { Label("My Team", systemImage: "star") }
                                    .tint(.accentColor)
                                Button {
                                    renameTarget = team
                                    renameText = team.name
                                } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fantasy Teams")
            .navigationDestination(for: FantasyTeam.self) { team in
                FantasyTeamDetailView(teamId: team.id)
            }
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
            }
        }
        .sheet(item: $builderTeam) { target in
            FantasyTeamBuilderView(teamId: target.id, initialName: target.name)
                .environmentObject(fantasyTeamStore)
                .environmentObject(teamsVM)
                .environmentObject(fantasyStore)
                .environmentObject(appSettings)
        }
        .alert("Rename Team", isPresented: renameBinding) {
            TextField("Team name", text: $renameText)
            Button("Save") {
                if let t = renameTarget { fantasyTeamStore.rename(t.id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    @ViewBuilder
    private func teamRow(_ team: FantasyTeam) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(.subheadline.bold())
                Text("\(team.playerSlugs.count) player\(team.playerSlugs.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if team.id == fantasyTeamStore.myTeamId {
                Text("My Team")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }
}
