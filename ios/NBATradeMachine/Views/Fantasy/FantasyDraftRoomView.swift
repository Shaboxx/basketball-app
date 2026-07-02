import SwiftUI

/// The league's draft room: start a snake draft over the league's member order,
/// pick from the available pool (sorted by the league's format value), auto-pick
/// best available, undo (commissioner), and — when the board fills — apply the
/// drafted rosters onto the teams (OVERWRITING their current rosters).
struct FantasyDraftRoomView: View {
    @EnvironmentObject var fantasyDraftStore: FantasyDraftStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID
    @State private var query = ""
    @State private var confirmApply = false

    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }
    private var draft: FantasyDraft? { fantasyDraftStore.draft(for: leagueId) }
    private var format: FantasyFormat {
        league?.rules.effectiveFormat(appDefault: appSettings.fantasyFormat)
            ?? appSettings.fantasyFormat
    }
    /// Rounds = the league's roster shape (or the app-wide one).
    private var rounds: Int {
        (league?.rules.limits ?? appSettings.fantasyRosterLimits).total
    }
    private var memberIds: [UUID] {
        (league?.teamIds ?? []).filter { fantasyTeamStore.team($0) != nil }
    }

    private var taken: Set<String> { draft.map(FantasyDraftEngine.takenSlugs) ?? [] }

    /// Draft-order teams that were deleted or removed from the league mid-draft.
    /// Picks must not accrue to a ghost, and apply must not partially write.
    private var danglingIds: [UUID] {
        (draft?.order ?? []).filter {
            fantasyTeamStore.team($0) == nil || !(league?.teamIds.contains($0) ?? false)
        }
    }

    /// Fantasy values still loading/failed → value ordering degrades to
    /// alphabetical; surface that instead of silently mis-drafting.
    private var valuesReady: Bool { !fantasyStore.values.isEmpty }

    private var available: [Player] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = teamsVM.allRosteredPlayers.filter {
            !taken.contains(FantasyValueStore.canonicalSlug($0.slug))
                && (q.isEmpty || $0.name.lowercased().contains(q))
        }
        return FantasyPlayerOrdering.byValue(pool, values: fantasyStore.values, format: format)
    }

    var body: some View {
        NavigationStack {
            List {
                if let draft {
                    boardSections(draft)
                } else {
                    startSection
                }
            }
            .searchable(text: $query, prompt: "Search available players")
            .navigationTitle("Draft Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Start

    @ViewBuilder private var startSection: some View {
        Section {
            if memberIds.count < 2 {
                Text("Add at least two teams to the league to draft.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    fantasyDraftStore.startDraft(leagueId: leagueId, order: memberIds, rounds: rounds)
                } label: {
                    Label("Start Draft", systemImage: "play.circle.fill")
                }
            }
        } header: {
            Text("Snake Draft")
        } footer: {
            Text("\(memberIds.count) teams · \(rounds) rounds, snaking each round. Draft order = the league's member order (reorder members in League Settings first).")
        }
    }

    // MARK: Board

    @ViewBuilder private func boardSections(_ draft: FantasyDraft) -> some View {
        if !danglingIds.isEmpty && draft.status != .applied {
            Section {
                Label("A drafting team was deleted or removed from the league — reset the draft (Commissioner menu) to continue.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            clockSection(draft)
        }
        if !draft.picks.isEmpty { recentPicksSection(draft) }
        if draft.status == .inProgress && danglingIds.isEmpty {
            if !valuesReady {
                Section {
                    Label("Player values are still loading — the list below is alphabetical until they arrive.",
                          systemImage: "hourglass")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            availableSection(draft)
        }
    }

    @ViewBuilder private func clockSection(_ draft: FantasyDraft) -> some View {
        Section {
            switch draft.status {
            case .inProgress:
                if let team = FantasyDraftEngine.onTheClock(draft) {
                    let overall = draft.picks.count + 1
                    let round = FantasyDraftEngine.round(forOverall: overall, teams: draft.order.count)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Round \(round) · Pick \(overall) of \(FantasyDraftEngine.totalPicks(draft))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(fantasyTeamStore.team(team)?.name ?? "Team") is on the clock")
                            .font(.headline)
                    }
                    Button {
                        autoPick(draft)
                    } label: {
                        Label("Auto-Pick Best Available", systemImage: "wand.and.stars")
                    }
                    .disabled(!valuesReady)   // no values → "best" would be alphabetical
                }
            case .complete:
                Text("Draft complete — apply the rosters to the teams.").font(.headline)
                Button {
                    confirmApply = true
                } label: {
                    Label("Apply Rosters to Teams", systemImage: "checkmark.circle.fill")
                }
                .confirmationDialog("Applying overwrites each team's current roster with its drafted players.",
                                    isPresented: $confirmApply, titleVisibility: .visible) {
                    Button("Apply Rosters", role: .destructive) { applyRosters(draft) }
                    Button("Cancel", role: .cancel) {}
                }
            case .applied:
                Label("Draft applied — rosters are live on the teams.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder private func recentPicksSection(_ draft: FantasyDraft) -> some View {
        Section("Recent Picks") {
            ForEach(draft.picks.suffix(5).reversed(), id: \.overall) { pick in
                HStack {
                    Text("\(pick.overall).").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(playerName(pick.slug)).font(.subheadline)
                        Text(fantasyTeamStore.team(pick.teamId)?.name ?? "Team")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if draft.status != .applied {
                Button(role: .destructive) {
                    fantasyDraftStore.undoLastPick(leagueId: leagueId)
                } label: {
                    Label("Undo Last Pick", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    @ViewBuilder private func availableSection(_ draft: FantasyDraft) -> some View {
        Section("Available (\(available.count))") {
            ForEach(available.prefix(60)) { p in
                Button {
                    fantasyDraftStore.makePick(leagueId: leagueId, slug: p.slug)
                } label: {
                    HStack(spacing: 10) {
                        HeadshotImage(slug: p.slug, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.subheadline).lineLimit(1)
                            Text("\(p.teamId) · \(p.position)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if let fv = fantasyStore.value(for: p.slug) {
                            Text(String(format: "%.1f", format.entry(in: fv).value))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Image(systemName: "plus.circle").foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func autoPick(_ draft: FantasyDraft) {
        if let best = FantasyDraftEngine.bestAvailable(
            pool: teamsVM.allRosteredPlayers, values: fantasyStore.values,
            format: format, taken: FantasyDraftEngine.takenSlugs(draft)) {
            fantasyDraftStore.makePick(leagueId: leagueId, slug: best.slug)
        }
    }

    private func applyRosters(_ draft: FantasyDraft) {
        // Never stamp applied over a partial write: every draft-order team must
        // still resolve (the dangling guard hides Apply, but belt-and-suspenders).
        guard danglingIds.isEmpty else { return }
        let drafted = FantasyDraftEngine.rosters(draft)
        // Apply over the league's CURRENT membership: a team added after the
        // draft started drafted nobody, so its roster empties rather than
        // silently keeping pre-draft players.
        for id in (league?.teamIds ?? []) where fantasyTeamStore.team(id) != nil {
            fantasyTeamStore.setRoster(drafted[id] ?? [], for: id)
        }
        fantasyDraftStore.markApplied(leagueId: leagueId)
    }

    private func playerName(_ slug: String) -> String {
        teamsVM.allRosteredPlayers.first {
            FantasyValueStore.canonicalSlug($0.slug) == slug
        }?.name ?? slug
    }
}
