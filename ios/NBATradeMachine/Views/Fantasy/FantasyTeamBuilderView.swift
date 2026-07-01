import SwiftUI

/// Build or edit one saved fantasy team. Holds only `teamId` (+ a local name draft);
/// all roster mutations route through `FantasyTeamStore`. Search-add over the whole
/// league pool, reorder (`.onMove`), remove (`.onDelete` / per-row), rename, delete.
struct FantasyTeamBuilderView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @Environment(\.dismiss) private var dismiss

    let teamId: UUID
    @State private var name: String
    @State private var query = ""

    init(teamId: UUID, initialName: String) {
        self.teamId = teamId
        _name = State(initialValue: initialName)
    }

    /// Canonical-slug → Player display index over the loaded league pool.
    private var playerBySlug: [String: Player] {
        Dictionary(
            teamsVM.allRosteredPlayers.map { (FantasyValueStore.canonicalSlug($0.slug), $0) },
            uniquingKeysWith: { a, _ in a })
    }

    /// The current (persisted) roster slugs for this team.
    private var rosterSlugs: [String] { fantasyTeamStore.team(teamId)?.playerSlugs ?? [] }

    /// Canonical set of the roster, for the add-list "already added" check.
    private var rosterCanonSet: Set<String> {
        Set(rosterSlugs.map { FantasyValueStore.canonicalSlug($0) })
    }

    /// Search results over the league pool (name/slug contains, case-insensitive).
    private var filtered: [Player] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return teamsVM.allRosteredPlayers.sorted { $0.name < $1.name } }
        return teamsVM.allRosteredPlayers
            .filter { $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team Name") {
                    TextField("Team name", text: $name)
                        .onChange(of: name) { _, newValue in
                            fantasyTeamStore.rename(teamId, to: newValue)
                        }
                }

                Section("Roster (\(rosterSlugs.count))") {
                    if rosterSlugs.isEmpty {
                        Text("No players yet — add from below.").foregroundStyle(.secondary)
                    } else {
                        ForEach(rosterSlugs, id: \.self) { slug in rosterRow(slug) }
                            .onMove { source, destination in
                                fantasyTeamStore.movePlayer(in: teamId, from: source, to: destination)
                            }
                            .onDelete { offsets in
                                for slug in offsets.map({ rosterSlugs[$0] }) {
                                    fantasyTeamStore.removePlayer(slug, from: teamId)
                                }
                            }
                    }
                }

                Section("Add Players") {
                    ForEach(filtered) { p in addRow(p) }
                }
            }
            .searchable(text: $query, prompt: "Search players")
            .navigationTitle("Edit Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive) {
                        fantasyTeamStore.delete(teamId)
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
    private func rosterRow(_ slug: String) -> some View {
        HStack(spacing: 12) {
            HeadshotImage(slug: playerBySlug[slug]?.slug ?? slug, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(playerBySlug[slug]?.name ?? slug).font(.subheadline)
                if let pos = playerBySlug[slug]?.position {
                    Text(pos).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                fantasyTeamStore.removePlayer(slug, from: teamId)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func addRow(_ p: Player) -> some View {
        let added = rosterCanonSet.contains(FantasyValueStore.canonicalSlug(p.slug))
        Button {
            if !added { fantasyTeamStore.addPlayer(p.slug, to: teamId) }
        } label: {
            HStack(spacing: 12) {
                HeadshotImage(slug: p.slug, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.subheadline)
                    Text("\(p.teamId) · \(p.position)").font(.caption).foregroundStyle(.secondary)
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
