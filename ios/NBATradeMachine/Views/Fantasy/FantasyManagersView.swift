import SwiftUI

/// Commissioner manager management: the league's people, who runs which team, and
/// who the commissioner is. Assigning a manager to a team also sets that team's
/// owner name (the single display source on the Teams grid). Names are
/// profanity-gated and de-duplicated within the league.
struct FantasyManagersView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID

    @State private var newManager = ""
    @State private var addError: String?
    @State private var renameTarget: FantasyManager?
    @State private var renameText = ""

    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }
    private var managers: [FantasyManager] { league?.managers ?? [] }
    private var memberTeams: [FantasyTeam] {
        (league?.teamIds ?? []).compactMap { fantasyTeamStore.team($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                managersSection
                if !managers.isEmpty {
                    assignmentsSection
                    commissionerSection
                }
            }
            .navigationTitle("Managers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename Manager", isPresented: renameBinding) {
                TextField("Name", text: $renameText)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }

    // MARK: Managers

    @ViewBuilder private var managersSection: some View {
        Section {
            ForEach(managers) { m in
                HStack {
                    Text(m.name)
                    if league?.commissionerId == m.id {
                        Text("Commissioner").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Button {
                        renameTarget = m; renameText = m.name
                    } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) { removeManager(m) } label: { Label("Remove", systemImage: "trash") }
                }
            }
            HStack {
                TextField("Add manager", text: $newManager)
                Button("Add") { addManager() }.disabled(newManager.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Managers")
        } footer: {
            if let addError { Text(addError).foregroundStyle(.red) }
            else { Text("Add each person in your league. Assign them to teams below.") }
        }
    }

    private func addManager() {
        let name = newManager.trimmingCharacters(in: .whitespacesAndNewlines)
        if FantasyNameRules.readsProfane(name) { addError = "That name isn't allowed."; return }
        if FantasyNameRules.isDuplicate(name, in: managers.map(\.name)) {
            addError = "A manager with that name already exists."; return
        }
        addError = nil
        fantasyLeagueStore.addManager(name: name, to: leagueId)
        newManager = ""
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func commitRename() {
        guard let m = renameTarget else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = managers.filter { $0.id != m.id }.map(\.name)
        if name.isEmpty { addError = "Enter a name." }
        else if FantasyNameRules.readsProfane(name) { addError = "That name isn't allowed." }
        else if FantasyNameRules.isDuplicate(name, in: others) { addError = "A manager with that name already exists." }
        else {
            addError = nil
            fantasyLeagueStore.renameManager(m.id, to: name, in: leagueId)
            // Re-push the new name onto every team this manager runs.
            for team in memberTeams where league?.teamManager[team.id] == m.id {
                fantasyTeamStore.setOwner(name, for: team.id)
            }
        }
        renameTarget = nil
    }

    /// Remove a manager AND clear the owner name of every team they ran (so the
    /// grid doesn't keep showing a phantom owner after removal).
    private func removeManager(_ m: FantasyManager) {
        for team in memberTeams where league?.teamManager[team.id] == m.id {
            fantasyTeamStore.setOwner("", for: team.id)
        }
        fantasyLeagueStore.removeManager(m.id, from: leagueId)
    }

    // MARK: Team assignments

    @ViewBuilder private var assignmentsSection: some View {
        Section {
            if memberTeams.isEmpty {
                Text("Add teams to the league to assign managers.").foregroundStyle(.secondary)
            } else {
                ForEach(memberTeams) { team in
                    HStack {
                        Text(team.name)
                        Spacer()
                        Menu {
                            Button("Unassigned") { assign(nil, to: team.id) }
                            ForEach(managers) { m in
                                Button(m.name) { assign(m.id, to: team.id) }
                            }
                        } label: {
                            Text(league?.manager(league?.teamManager[team.id])?.name ?? "Unassigned")
                                .font(.subheadline).foregroundStyle(.tint)
                        }
                    }
                }
            }
        } header: {
            Text("Team Assignments")
        } footer: {
            Text("Assigning a manager sets the team's owner name shown on the Teams grid.")
        }
    }

    private func assign(_ managerId: UUID?, to teamId: UUID) {
        let name = fantasyLeagueStore.assignManager(managerId, toTeam: teamId, in: leagueId)
        // Explicit unassign clears the owner name; assign pushes the manager's name.
        if managerId == nil { fantasyTeamStore.setOwner("", for: teamId) }
        else if let name { fantasyTeamStore.setOwner(name, for: teamId) }
    }

    // MARK: Commissioner

    @ViewBuilder private var commissionerSection: some View {
        Section {
            Picker("Commissioner", selection: Binding(
                get: { league?.commissionerId },
                set: { fantasyLeagueStore.setCommissioner($0, in: leagueId) })) {
                Text("None").tag(UUID?.none)
                ForEach(managers) { m in Text(m.name).tag(UUID?.some(m.id)) }
            }
        } header: {
            Text("Commissioner")
        } footer: {
            Text("The commissioner runs the draft, trades, and league settings.")
        }
    }
}
