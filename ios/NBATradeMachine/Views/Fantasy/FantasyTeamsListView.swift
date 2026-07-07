import SwiftUI
import UIKit

/// Fantasy-mode Teams surface, laid out like the NBA Teams grid: three columns
/// of cards — user logo (or placeholder) where the NBA logo sits, the team's
/// INITIALS in the abbreviation slot, the team name in the name slot, the
/// OWNER's name in the city slot, then "#seed" (current standing in the first
/// league the team belongs to, or a dash) and the team GRADE where the NBA grid
/// shows OFF/DEF. Long-press a card for My Team / Rename / Delete.
struct FantasyTeamsListView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyActualsStore: FantasyActualsStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @EnvironmentObject var footerState: FooterState
    // Held only to forward into the pushed detail views (see the navigationDestinations):
    // a `.navigationDestination` destination does not reliably inherit this stack's
    // @EnvironmentObjects, so each destination is injected explicitly — mirroring the
    // sheet-injection pattern used across the app. Without this, opening a team crashed
    // with "No ObservableObject of type FantasyTeamStore found."
    @EnvironmentObject var todayGamesStore: TodayGamesStore

    @State private var path = NavigationPath()
    @State private var builderTeam: BuilderTarget?
    @State private var renameTarget: FantasyTeam?
    @State private var renameText: String = ""
    @State private var deleteTarget: FantasyTeam?

    /// Identifiable wrapper so `.sheet(item:)` builds the builder once a team exists.
    private struct BuilderTarget: Identifiable {
        let id: UUID
        let name: String
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        let id = fantasyTeamStore.createTeam(name: "My Team")
                        builderTeam = BuilderTarget(id: id, name: fantasyTeamStore.team(id)?.name ?? "My Team")
                    } label: {
                        Label("New Team", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if fantasyTeamStore.teams.isEmpty {
                        Text("No fantasy teams yet — tap New Team to build one.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(fantasyTeamStore.teams) { team in
                                NavigationLink(value: team) { teamCell(team) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .reportsFooterScroll(footerState)
            .navigationTitle("")   // app header row already reads "Fantasy" (avoid the duplicate)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FantasyTeam.self) { team in
                // Explicitly inject every store the detail view reads — the pushed
                // destination doesn't inherit this stack's environment (fixes the
                // missing-FantasyTeamStore crash on tapping a team).
                FantasyTeamDetailView(teamId: team.id)
                    .environmentObject(fantasyTeamStore)
                    .environmentObject(fantasyStore)
                    .environmentObject(teamsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyActualsStore)
                    .environmentObject(todayGamesStore)
                    .environmentObject(normsVM)
                    .environmentObject(fantasyLeagueStore)
                    .environmentObject(fantasyTradeStore)
            }
            .navigationDestination(for: Player.self) { p in
                PlayerDetailView(player: p)
                    .environmentObject(teamsVM)
                    .environmentObject(normsVM)
                    .environmentObject(appSettings)
                    .environmentObject(fantasyStore)
            }
        }
        .sheet(item: $builderTeam) { target in
            FantasyTeamBuilderView(teamId: target.id, initialName: target.name)
                .environmentObject(fantasyTeamStore)
                .environmentObject(teamsVM)
                .environmentObject(fantasyStore)
                .environmentObject(appSettings)
                .environmentObject(normsVM)
                .environmentObject(fantasyLeagueStore)
        }
        .alert("Rename Team", isPresented: renameBinding) {
            TextField("Team name", text: $renameText)
            Button("Save") {
                if let t = renameTarget,
                   !FantasyNameRules.readsProfane(renameText),
                   !FantasyNameRules.isDuplicate(renameText, in: siblingLeagueNames(of: t.id)) {
                    fantasyTeamStore.rename(t.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Profanity and names already used in one of the team's leagues are rejected.")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    // MARK: Cell (mirrors the NBA teams grid slots)

    @ViewBuilder
    private func teamCell(_ team: FantasyTeam) -> some View {
        VStack(spacing: 3) {
            logoView(team)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            Text(team.initials.isEmpty ? "—" : team.initials)
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(team.name)
                .font(.subheadline.bold())
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(team.ownerName.isEmpty ? " " : team.ownerName)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Text(bottomLine(team))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if fantasyTeamStore.myTeamId == team.id {
                Image(systemName: "star.fill")
                    .font(.caption2).foregroundStyle(Color.accentColor)
                    .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if isIncomplete(team) {
                Image(systemName: "flag.fill")
                    .font(.caption2).foregroundStyle(.red)
                    .padding(6)
                    .accessibilityLabel("Incomplete team")
            }
        }
        .contextMenu {
            Button { fantasyTeamStore.setMyTeam(team.id) } label: {
                Label("Set as My Team", systemImage: "star")
            }
            Button {
                renameTarget = team
                renameText = team.name
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { deleteTarget = team } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Are you sure you want to delete the team?",
                            isPresented: Binding(get: { deleteTarget?.id == team.id },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Team", role: .destructive) {
                if let t = deleteTarget {
                    fantasyTradeStore.removeTrades(involving: t.id)   // purge its dangling trades
                    fantasyTeamStore.delete(t.id)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
    }

    @ViewBuilder
    private func logoView(_ team: FantasyTeam) -> some View {
        if let fn = team.logoFileName,
           let data = FantasyLogoStore.imageData(named: fn),
           let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            // Default placeholder until the owner picks a photo.
            Image(systemName: "basketball.circle.fill")
                .resizable().scaledToFit()
                .foregroundStyle(.orange.opacity(0.75))
        }
    }

    /// "#seed · Grade B+" — standing in the FIRST league containing the team
    /// (dash when unaffiliated), grade where the NBA grid shows OFF/DEF.
    private func bottomLine(_ team: FantasyTeam) -> String {
        let seed = standing(team).map { "#\($0)" } ?? "—"
        let grade = gradeLetter(team) ?? "—"
        return "\(seed) · Grade \(grade)"
    }

    /// Red-flag rule: no league affiliation, or roster short of the lineup size —
    /// using the team's ENFORCED limits (governing-league override, else app-wide).
    private func isIncomplete(_ team: FantasyTeam) -> Bool {
        let inLeague = fantasyLeagueStore.firstLeague(containing: team.id) != nil
        let lineup = fantasyLeagueStore.effectiveLimits(
            for: team.id, appWide: appSettings.fantasyRosterLimits).lineup
        return FantasyTeamCompleteness.isIncomplete(
            playerCount: team.playerSlugs.count,
            inAnyLeague: inLeague,
            lineupLimit: lineup)
    }

    /// Names of every OTHER team sharing a league with `teamId` (rename guard).
    private func siblingLeagueNames(of teamId: UUID) -> [String] {
        fantasyLeagueStore.leagues
            .filter { $0.teamIds.contains(teamId) }
            .flatMap(\.teamIds)
            .filter { $0 != teamId }
            .compactMap { fantasyTeamStore.team($0)?.name }
    }

    private func standing(_ team: FantasyTeam) -> Int? {
        guard let league = fantasyLeagueStore.firstLeague(containing: team.id) else { return nil }
        let members = league.teamIds.compactMap { fantasyTeamStore.team($0) }
        guard members.count >= 2 else { return nil }
        // Dream Team seeds need the ownership-split productions the league detail view
        // builds; rather than duplicate that resolution here, defer the seed to that
        // authoritative screen (the grid shows "—" instead of an un-split, wrong rank).
        guard league.mode != .dreamTeam else { return nil }
        let fmt = league.rules.effectiveFormat(appDefault: appSettings.fantasyFormat)
        // Live standings are only trustworthy once EVERY team has season-to-date data —
        // a zero-resolved team's to=0 poisons raw-rate scoring — so mirror the detail
        // view, which refuses to compute (shows a note) until then, rather than seed
        // the grid off garbage.
        if appSettings.statSource == .live {
            let unresolved = FantasyLiveResolution.unresolvedTeams(
                teams: members, actuals: fantasyActualsStore.actualsBySlug,
                season: fantasyActualsStore.season)
            guard unresolved.isEmpty else { return nil }
        }
        // Same stat source the league detail scores with (projected or live).
        let src: FantasyStatSource = appSettings.statSource == .live
            ? ActualsStatSource(actuals: fantasyActualsStore.actualsBySlug,
                                season: fantasyActualsStore.season)
            : ProjectedStatSource(values: fantasyStore.values)
        let prods = Dictionary(members.map { ($0.id, src.production(for: $0, format: fmt)) },
                               uniquingKeysWith: { a, _ in a })
        let ids = members.map(\.id)
        let rows = FantasyStandings.standings(
            productions: prods, teamIds: ids,
            schedule: FantasyLeagueSchedule.resolved(teamIds: ids,
                                                     regularSeasonWeeks: league.rules.regularSeasonWeeks),
            format: fmt,
            customCategories: league.rules.effectiveCustomCategories)
        return rows.first { $0.teamId == team.id }?.rank
    }

    private func gradeLetter(_ team: FantasyTeam) -> String? {
        // Limits AND format come from the team's governing league (single source),
        // so the grade is fully league-consistent — mirroring standing().
        let assignments = FantasyRosterSlots.effectiveAssignments(
            roster: team.playerSlugs, stored: team.slots,
            limits: fantasyLeagueStore.effectiveLimits(
                for: team.id, appWide: appSettings.fantasyRosterLimits))
        let lineup = FantasyRosterSlots.slugs(in: .lineup, roster: team.playerSlugs,
                                              assignments: assignments)
        let fmt = fantasyLeagueStore.firstLeague(containing: team.id)?
            .rules.effectiveFormat(appDefault: appSettings.fantasyFormat) ?? appSettings.fantasyFormat
        let pool = FantasyGrading.rankedPoolCount(values: fantasyStore.values, format: fmt)
        return FantasyGrading.teamPercentile(slugs: lineup, values: fantasyStore.values,
                                             format: fmt, poolCount: pool)
            .map(FantasyGrading.letter(forPercentile:))
    }
}
