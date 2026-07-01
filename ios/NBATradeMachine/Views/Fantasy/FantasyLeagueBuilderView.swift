import SwiftUI

/// Build or edit one saved league. Holds only `leagueId` (+ a local name draft); every
/// edit routes through `FantasyLeagueStore`, and the member list reads the current
/// `fantasyLeagueStore.league(leagueId)?.teamIds`. Add/remove/reorder member teams;
/// rename; delete. Mirrors `FantasyTeamBuilderView`.
struct FantasyLeagueBuilderView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID
    @State private var name: String = ""

    init(leagueId: UUID) { self.leagueId = leagueId }

    /// The current (persisted) member team ids for this league.
    private var memberIds: [UUID] { fantasyLeagueStore.league(leagueId)?.teamIds ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section("League Name") {
                    TextField("League name", text: $name)
                        .onChange(of: name) { _, newValue in
                            fantasyLeagueStore.rename(leagueId, to: newValue)
                        }
                }

                Section("Members (\(memberIds.count))") {
                    if memberIds.isEmpty {
                        Text("No teams yet — add at least two from below.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memberIds, id: \.self) { teamId in memberRow(teamId) }
                            .onMove { source, destination in
                                fantasyLeagueStore.moveTeam(in: leagueId, from: source, to: destination)
                            }
                            .onDelete { offsets in
                                for teamId in offsets.map({ memberIds[$0] }) {
                                    fantasyLeagueStore.removeTeam(teamId, from: leagueId)
                                }
                            }
                    }
                }

                Section("Add Teams") {
                    if fantasyTeamStore.teams.count < 2 {
                        Text("Create fantasy teams first (Teams tab), then add at least two here to see standings.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(fantasyTeamStore.teams) { team in addRow(team) }
                }
            }
            .navigationTitle("Edit League")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = fantasyLeagueStore.league(leagueId)?.name ?? "" }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive) {
                        fantasyLeagueStore.delete(leagueId)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ teamId: UUID) -> some View {
        HStack {
            if let team = fantasyTeamStore.team(teamId) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.subheadline)
                    Text("\(team.playerSlugs.count) player\(team.playerSlugs.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                // A dangling id (deleted team) renders a muted row so the user can clear it.
                Text("Removed team").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                fantasyLeagueStore.removeTeam(teamId, from: leagueId)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func addRow(_ team: FantasyTeam) -> some View {
        let added = memberIds.contains(team.id)
        Button {
            if !added { fantasyLeagueStore.addTeam(team.id, to: leagueId) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.subheadline)
                    Text("\(team.playerSlugs.count) player\(team.playerSlugs.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? .green : .accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(added)
    }
}
