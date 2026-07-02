import SwiftUI
import PhotosUI
import UIKit

/// Build or edit one saved fantasy team. Holds only `teamId` (+ local drafts);
/// all mutations route through `FantasyTeamStore`. Search-add over the whole
/// league pool (a tap toggles add/remove; the far-right arrow opens the player's
/// page and pops back with state intact), photo-library logo, owner name, rename,
/// delete.
struct FantasyTeamBuilderView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @Environment(\.dismiss) private var dismiss

    let teamId: UUID
    @State private var name: String
    @State private var query = ""
    @State private var nameError: String?
    @State private var owner = ""
    @State private var ownerError: String?
    @State private var logoItem: PhotosPickerItem?

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

    /// Search results over the league pool (name/slug contains, case-insensitive),
    /// ordered by the active format's fantasy value (best first; no-value players
    /// sink to the bottom) so the add list reads as a draft board.
    private var filtered: [Player] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = q.isEmpty
            ? teamsVM.allRosteredPlayers
            : teamsVM.allRosteredPlayers.filter {
                $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q)
            }
        return FantasyPlayerOrdering.byValue(pool, values: fantasyStore.values,
                                             format: appSettings.fantasyFormat)
    }

    /// Roster cap from the user's limits (lineup + bench + IR).
    private var rosterFull: Bool {
        rosterSlugs.count >= appSettings.fantasyRosterLimits.total
    }

    /// Names of every OTHER team sharing a league with this one — the rename
    /// duplicate check mirrors the league builder's add-time guard.
    private var siblingLeagueNames: [String] {
        fantasyLeagueStore.leagues
            .filter { $0.teamIds.contains(teamId) }
            .flatMap(\.teamIds)
            .filter { $0 != teamId }
            .compactMap { fantasyTeamStore.team($0)?.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Team name", text: $name)
                        .onChange(of: name) { _, newValue in
                            // Gated per keystroke with readsProfane (also rejects
                            // near-profane prefixes like "Fucke") + sibling-league
                            // duplicate check: an invalid draft shows the error and
                            // is NOT persisted (the store keeps the last clean value).
                            if FantasyNameRules.readsProfane(newValue) {
                                nameError = "That name isn't allowed."
                            } else if FantasyNameRules.isDuplicate(newValue, in: siblingLeagueNames) {
                                nameError = "A team in one of your leagues already uses that name."
                            } else {
                                nameError = nil
                                fantasyTeamStore.rename(teamId, to: newValue)
                            }
                        }
                } header: {
                    Text("Team Name")
                } footer: {
                    if let nameError { Text(nameError).foregroundStyle(.red) }
                }

                Section {
                    HStack(spacing: 12) {
                        logoPreview
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Label("Choose Logo Photo", systemImage: "photo")
                        }
                    }
                    TextField("Owner name", text: $owner)
                        .onChange(of: owner) { _, newValue in
                            if FantasyNameRules.readsProfane(newValue) {
                                ownerError = "That name isn't allowed."
                            } else {
                                ownerError = nil
                                fantasyTeamStore.setOwner(newValue, for: teamId)
                            }
                        }
                } header: {
                    Text("Logo & Owner")
                } footer: {
                    if let ownerError { Text(ownerError).foregroundStyle(.red) }
                    else { Text("The logo and owner name show on your team's card in the Teams grid.") }
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

                Section {
                    ForEach(filtered) { p in addRow(p) }
                } header: {
                    Text("Add Players")
                } footer: {
                    if rosterFull {
                        Text("Roster limit reached (\(appSettings.fantasyRosterLimits.total)). Adjust limits in Fantasy Settings or remove a player.")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search players")
            .navigationTitle("Edit Team")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { owner = fantasyTeamStore.team(teamId)?.ownerName ?? "" }
            .onChange(of: logoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let fileName = FantasyLogoStore.save(data, teamId: teamId) {
                        fantasyTeamStore.setLogo(fileName, for: teamId)
                    }
                }
            }
            .navigationDestination(for: Player.self) { p in
                // Pushed INSIDE the sheet's own stack, so popping back lands on this
                // roster list with the search text and every add/remove intact.
                PlayerDetailView(player: p)
            }
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
            }
        }
    }

    @ViewBuilder
    private var logoPreview: some View {
        Group {
            if let fn = fantasyTeamStore.team(teamId)?.logoFileName,
               let data = FantasyLogoStore.imageData(named: fn),
               let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "basketball.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.orange.opacity(0.75))
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
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
        let blocked = !added && rosterFull
        HStack(spacing: 12) {
            // Tap the row (or the check) to TOGGLE: add when absent, remove when
            // present — no Edit mode needed.
            Button {
                if added {
                    fantasyTeamStore.removePlayer(p.slug, from: teamId)
                } else if !rosterFull {
                    fantasyTeamStore.addPlayer(p.slug, to: teamId)
                }
            } label: {
                HStack(spacing: 12) {
                    HeadshotImage(slug: p.slug, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline)
                        Text("\(p.teamId) · \(p.position)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let fv = fantasyStore.value(for: p.slug) {
                        Text(String(format: "%.1f", appSettings.fantasyFormat.entry(in: fv).value))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(added ? .green : (blocked ? .secondary : .accentColor))
                }
            }
            .buttonStyle(.plain)
            .disabled(blocked)

            // Far-right arrow → the player's page (state-preserving push).
            NavigationLink(value: p) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
