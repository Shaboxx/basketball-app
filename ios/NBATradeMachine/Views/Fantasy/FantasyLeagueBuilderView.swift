import SwiftUI

/// Build or edit one saved league — the full ESPN/Yahoo-style setup: name,
/// scoring (presets or a custom category mask), roster shape, playoffs, entry
/// stakes (recorded + linked out, never processed), and members. Holds only
/// `leagueId`; every edit routes through `FantasyLeagueStore` (rules/stakes are
/// written through on change), and the member list reads the live store state.
struct FantasyLeagueBuilderView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyDraftStore: FantasyDraftStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID
    @State private var name: String = ""
    @State private var nameError: String?
    @State private var confirmDelete = false

    // Scoring draft state
    private enum ScoringChoice: Hashable {
        case followApp
        case preset(FantasyFormat)
        case custom
    }
    @State private var scoring: ScoringChoice = .followApp
    @State private var customCats: Set<FantasyLeagueCategory> = Set(FantasyLeagueCategory.allCases)

    // Roster draft state
    @State private var customRoster = false
    @State private var lineup = FantasyRosterLimits.standard.lineup
    @State private var bench = FantasyRosterLimits.standard.bench
    @State private var ir = FantasyRosterLimits.standard.ir

    // Playoffs draft state
    @State private var playoffsOn = false
    @State private var playoffTeams = 4
    @State private var playoffStartWeek = 1

    // Stakes draft state. Buy-in is string-backed: TextField(value:format:)
    // only commits on submit/focus-loss, and .decimalPad has no return key —
    // a per-keystroke string binding matches the form's persist-on-change contract.
    @State private var buyInText = ""
    @State private var dueBy = ""
    @State private var platform: FantasyPayPlatform?

    private var buyInValue: Double? {
        Double(buyInText.replacingOccurrences(of: ",", with: "."))
    }

    init(leagueId: UUID) { self.leagueId = leagueId }

    /// The current (persisted) member team ids for this league.
    private var memberIds: [UUID] { fantasyLeagueStore.league(leagueId)?.teamIds ?? [] }
    private var memberNames: [String] {
        memberIds.compactMap { fantasyTeamStore.team($0)?.name }
    }

    @State private var host: FantasyLeagueHost = .thisApp
    @State private var mode: FantasyLeagueMode = .standard

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                modeSection
                hostingSection
                scoringSection
                rosterSection
                playoffsSection
                stakesSection
                membersSection
                addTeamsSection
            }
            .navigationTitle("Edit League")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: adoptFromStore)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Are you sure you want to delete the league?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete League", role: .destructive) {
                    fantasyDraftStore.resetDraft(leagueId: leagueId)   // purge its draft blob
                    fantasyTradeStore.removeTrades(for: leagueId)      // purge its trade blobs
                    fantasyLeagueStore.delete(leagueId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Draft <-> store sync

    private func adoptFromStore() {
        guard let league = fantasyLeagueStore.league(leagueId) else { return }
        name = league.name
        host = league.host
        mode = league.mode
        if let custom = league.rules.effectiveCustomCategories {
            scoring = .custom
            customCats = Set(custom)
        } else if let f = league.rules.format {
            scoring = .preset(f)
        } else {
            scoring = .followApp
        }
        if let limits = league.rules.limits {
            customRoster = true
            lineup = limits.lineup; bench = limits.bench; ir = limits.ir
        }
        if let pt = league.rules.playoffTeams, pt >= 2 {
            playoffsOn = true
            playoffTeams = pt
            playoffStartWeek = league.rules.playoffStartWeek ?? 1
        }
        if let b = league.stakes.buyIn {
            buyInText = b == b.rounded() ? String(Int(b)) : String(b)
        } else {
            buyInText = ""
        }
        dueBy = league.stakes.dueBy ?? ""
        platform = league.stakes.platform
    }

    private func persistRules() {
        var rules = FantasyLeagueRules.none
        // The Schedule editor owns regular-season length; this builder must not wipe
        // it when it rebuilds rules from its own (scoring/roster/playoff) fields.
        rules.regularSeasonWeeks = fantasyLeagueStore.league(leagueId)?.rules.regularSeasonWeeks
        switch scoring {
        case .followApp:
            break
        case .preset(let f):
            rules.format = f
        case .custom:
            rules.customCategories = FantasyLeagueCategory.allCases.filter(customCats.contains)
        }
        if customRoster {
            rules.limits = FantasyRosterLimits(lineup: lineup, bench: bench, ir: ir)
        }
        if playoffsOn {
            rules.playoffTeams = playoffTeams
            rules.playoffStartWeek = playoffStartWeek
        }
        fantasyLeagueStore.setRules(rules, in: leagueId)
    }

    private func persistStakes() {
        fantasyLeagueStore.setStakes(
            FantasyLeagueStakes(buyIn: buyInValue,
                                dueBy: dueBy.isEmpty ? nil : dueBy,
                                platform: platform),
            in: leagueId)
    }

    // MARK: Sections

    @ViewBuilder private var nameSection: some View {
        Section {
            TextField("League name", text: $name)
                .onChange(of: name) { _, newValue in
                    if FantasyNameRules.readsProfane(newValue) {
                        nameError = "That name isn't allowed."
                    } else {
                        nameError = nil
                        fantasyLeagueStore.rename(leagueId, to: newValue)
                    }
                }
        } header: {
            Text("League Name")
        } footer: {
            if let nameError { Text(nameError).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(FantasyLeagueMode.allCases) { m in Text(m.displayName).tag(m) }
            }
            .onChange(of: mode) { _, m in fantasyLeagueStore.setMode(m, in: leagueId) }
        } header: {
            Text("Mode")
        } footer: {
            Text(mode == .dreamTeam
                 ? "Dream Team: any team may roster ANY NBA player. When two or more teams share a player, his counting stats are SPLIT between them (a 30-point night shared by 3 teams = 10 to each)."
                 : "Standard: each team scores its own roster.")
        }
    }

    @ViewBuilder private var hostingSection: some View {
        Section {
            Picker("Hosted on", selection: $host) {
                ForEach(FantasyLeagueHost.allCases) { h in
                    Text(h.displayName).tag(h)
                }
            }
            .onChange(of: host) { _, h in fantasyLeagueStore.setHost(h, in: leagueId) }
        } header: {
            Text("Hosting")
        } footer: {
            if host.supportsSync {
                Text("To pull in this league's teams + rosters automatically, use “Import League” on the Leagues screen (Sleeper, ESPN, and Fantrax now; Yahoo soon). Syncing OVERWRITES the imported league's data.")
            }
        }
    }

    @ViewBuilder private var scoringSection: some View {
        Section {
            Picker("Scoring", selection: $scoring) {
                Text("Follow App Setting").tag(ScoringChoice.followApp)
                ForEach(FantasyFormat.allCases) { f in
                    Text(f.displayName).tag(ScoringChoice.preset(f))
                }
                Text("Custom Categories").tag(ScoringChoice.custom)
            }
            .onChange(of: scoring) { _, _ in persistRules() }
            if scoring == .custom {
                ForEach(FantasyLeagueCategory.allCases, id: \.self) { cat in
                    Toggle(cat.label, isOn: Binding(
                        get: { customCats.contains(cat) },
                        set: { on in
                            if on { customCats.insert(cat) } else { customCats.remove(cat) }
                            persistRules()
                        }))
                }
            }
        } header: {
            Text("Scoring")
        } footer: {
            if scoring == .custom {
                Text(customCats.isEmpty
                     ? "Pick at least one category — an empty set falls back to the app format."
                     : "Custom leagues score head-to-head over the \(customCats.count) selected categor\(customCats.count == 1 ? "y" : "ies").")
            }
        }
    }

    @ViewBuilder private var rosterSection: some View {
        Section {
            Toggle("Custom roster sizes", isOn: $customRoster)
                .onChange(of: customRoster) { _, _ in persistRules() }
            if customRoster {
                Stepper("Lineup: \(lineup)", value: $lineup, in: 1...15)
                    .onChange(of: lineup) { _, _ in persistRules() }
                Stepper("Bench: \(bench)", value: $bench, in: 0...10)
                    .onChange(of: bench) { _, _ in persistRules() }
                Stepper("IR: \(ir)", value: $ir, in: 0...5)
                    .onChange(of: ir) { _, _ in persistRules() }
            }
        } header: {
            Text("Rosters")
        } footer: {
            Text(customRoster
                 ? "This league's teams carry \(lineup + bench + ir) players (\(lineup) lineup · \(bench) bench · \(ir) IR). Team building, slots, grading, and the draft ENFORCE these for member teams."
                 : "Uses your app-wide roster limits (Fantasy Settings).")
        }
    }

    @ViewBuilder private var playoffsSection: some View {
        Section {
            Toggle("Playoffs", isOn: $playoffsOn)
                .onChange(of: playoffsOn) { _, _ in persistRules() }
            if playoffsOn {
                Stepper("Playoff teams: \(playoffTeams)",
                        value: $playoffTeams, in: 2...max(2, max(memberIds.count, 2)))
                    .onChange(of: playoffTeams) { _, _ in persistRules() }
                Stepper("Start week: \(playoffStartWeek)",
                        value: $playoffStartWeek, in: 1...60)
                    .onChange(of: playoffStartWeek) { _, _ in persistRules() }
            }
        } header: {
            Text("Playoffs")
        } footer: {
            if playoffsOn {
                Text("Top \(playoffTeams) seeds by regular-season standings enter the bracket in week \(playoffStartWeek).")
            }
        }
    }

    @ViewBuilder private var stakesSection: some View {
        Section {
            HStack {
                Text("Buy-in ($)")
                Spacer()
                TextField("0", text: $buyInText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: buyInText) { _, _ in persistStakes() }
            }
            TextField("Due by (e.g. before draft night)", text: $dueBy)
                .onChange(of: dueBy) { _, _ in persistStakes() }
            Picker("Platform", selection: $platform) {
                Text("None").tag(FantasyPayPlatform?.none)
                ForEach(FantasyPayPlatform.allCases) { p in
                    Text(p.displayName).tag(FantasyPayPlatform?.some(p))
                }
            }
            .onChange(of: platform) { _, _ in persistStakes() }
            if let platform {
                Link(destination: platform.url) {
                    Label("Open \(platform.displayName)", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("Entry Stakes")
        } footer: {
            Text("Recorded for your league only — payments happen on the platform you pick, never in this app.")
        }
    }

    @ViewBuilder private var membersSection: some View {
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
    }

    @ViewBuilder private var addTeamsSection: some View {
        Section {
            if fantasyTeamStore.teams.count < 2 {
                Text("Create fantasy teams first (Teams tab), then add at least two here to see standings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(fantasyTeamStore.teams) { team in addRow(team) }
        } header: {
            Text("Add Teams")
        } footer: {
            Text("Two teams can't share a name in the same league.")
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
        // Duplicate-name guard: a would-be member whose (normalized) name collides
        // with an existing member's name can't join until one is renamed.
        let nameTaken = !added && FantasyNameRules.isDuplicate(team.name, in: memberNames)
        // Single-league membership: a team already in ANOTHER league can't join.
        let otherLeague = added ? nil : fantasyLeagueStore.otherLeague(for: team.id, excluding: leagueId)
        let blocked = nameTaken || otherLeague != nil
        Button {
            if !added && !blocked { fantasyLeagueStore.addTeam(team.id, to: leagueId) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.subheadline)
                    if nameTaken {
                        Text("Name already used in this league").font(.caption).foregroundStyle(.red)
                    } else if let other = otherLeague {
                        Text("Already in \(other.name)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(team.playerSlugs.count) player\(team.playerSlugs.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? .green : (blocked ? .secondary : .accentColor))
            }
        }
        .buttonStyle(.plain)
        .disabled(added || blocked)
    }
}
