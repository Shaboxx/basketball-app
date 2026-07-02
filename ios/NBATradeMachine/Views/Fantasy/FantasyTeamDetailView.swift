import SwiftUI

/// One saved team: roster rows (tap → PlayerDetailView) + a category-profile card
/// ("Value above replacement", or the points fp/game total). Reads the store +
/// FantasyTeamProfile / FantasySideValue.
struct FantasyTeamDetailView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var fantasyActualsStore: FantasyActualsStore
    @EnvironmentObject var todayGamesStore: TodayGamesStore
    @EnvironmentObject var normsVM: LeagueNormsViewModel
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore

    let teamId: UUID
    @State private var showBuilder = false

    private var team: FantasyTeam? { fantasyTeamStore.team(teamId) }
    private var isMyTeam: Bool { fantasyTeamStore.myTeamId == teamId }

    private var playerBySlug: [String: Player] {
        Dictionary(
            teamsVM.allRosteredPlayers.map { (FantasyValueStore.canonicalSlug($0.slug), $0) },
            uniquingKeysWith: { a, _ in a })
    }

    /// Resolved FantasyValues for the roster (store misses dropped).
    private var resolved: [FantasyValue] {
        (team?.playerSlugs ?? []).compactMap { fantasyStore.value(for: $0) }
    }

    // MARK: Slots (limits from settings; stored choices + auto-fill)
    private var limits: FantasyRosterLimits { appSettings.fantasyRosterLimits }
    private var roster: [String] { team?.playerSlugs ?? [] }
    private var assignments: [String: FantasySlot] {
        FantasyRosterSlots.effectiveAssignments(roster: roster,
                                                stored: team?.slots ?? [:],
                                                limits: limits)
    }
    private func slugs(in slot: FantasySlot) -> [String] {
        FantasyRosterSlots.slugs(in: slot, roster: roster, assignments: assignments)
    }
    private var lineupSlugs: [String] { slugs(in: .lineup) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                gradeCard
                rosterCard
                profileCard
            }
            .padding()
        }
        .navigationTitle(team?.name ?? "Team")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBuilder) {
            if let team {
                FantasyTeamBuilderView(teamId: team.id, initialName: team.name)
                    .environmentObject(fantasyTeamStore)
                    .environmentObject(teamsVM)
                    .environmentObject(fantasyStore)
                    .environmentObject(appSettings)
                    .environmentObject(normsVM)
                    .environmentObject(fantasyLeagueStore)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text(team?.name ?? "Team").font(.title2.bold())
                if isMyTeam { myTeamBadge }
                Spacer()
            }
            HStack(spacing: 10) {
                Button { showBuilder = true } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.bordered)
                if !isMyTeam {
                    Button { fantasyTeamStore.setMyTeam(teamId) } label: {
                        Label("Set as My Team", systemImage: "star")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
    }

    private var myTeamBadge: some View {
        Text("My Team")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: Grade card

    /// Percentile denominator = the RANKED population for the active format
    /// (ranks cover only the top of the pool; doc count would inflate grades).
    private var poolCount: Int {
        FantasyGrading.rankedPoolCount(values: fantasyStore.values,
                                       format: appSettings.fantasyFormat)
    }

    /// Lineup players whose NBA team has a game today.
    private var playingToday: [String] {
        lineupSlugs.filter { slug in
            guard let p = playerBySlug[slug] else { return false }
            return todayGamesStore.teamsPlayingToday.contains(p.teamId)
        }
    }

    @ViewBuilder
    private var gradeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Team Grade").font(.headline)
            HStack {
                Text("Overall").foregroundStyle(.secondary)
                Spacer()
                if let p = FantasyGrading.teamPercentile(
                    slugs: lineupSlugs, values: fantasyStore.values,
                    format: appSettings.fantasyFormat, poolCount: poolCount) {
                    gradeBadge(FantasyGrading.letter(forPercentile: p))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            Text("Lineup strength vs the top \(poolCount) ranked players (\(appSettings.fantasyFormat.displayName)).")
                .font(.caption2).foregroundStyle(.secondary)

            Divider()
            HStack {
                Text("Today").foregroundStyle(.secondary)
                Spacer()
                todayGradeValue
            }
            if !playingToday.isEmpty {
                Text("\(playingToday.count) of \(lineupSlugs.count) lineup players play today. Expected lines (\(appSettings.statSource == .live ? "season-to-date" : "projected") per-game):")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(playingToday, id: \.self) { slug in forecastRow(slug) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Today's grade: only lineup players WITH a game today count — an off-night
    /// roster honestly reads "No games today" instead of repeating the overall grade.
    @ViewBuilder
    private var todayGradeValue: some View {
        switch todayGamesStore.phase {
        case .idle, .loading:
            ProgressView()
        case .failed:
            Text("Schedule unavailable").font(.caption).foregroundStyle(.secondary)
        default:
            if playingToday.isEmpty {
                Text("No games today").font(.caption).foregroundStyle(.secondary)
            } else if let p = FantasyGrading.teamPercentile(
                slugs: playingToday, values: fantasyStore.values,
                format: appSettings.fantasyFormat, poolCount: poolCount) {
                gradeBadge(FantasyGrading.letter(forPercentile: p))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func forecastRow(_ slug: String) -> some View {
        if let line = FantasyTodayForecast.line(
            slug: slug, source: appSettings.statSource, format: appSettings.fantasyFormat,
            values: fantasyStore.values, actuals: fantasyActualsStore.actualsBySlug,
            actualsSeason: fantasyActualsStore.season) {
            HStack {
                Text(playerBySlug[slug]?.name ?? slug).font(.caption)
                Spacer()
                Text(forecastText(line))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func forecastText(_ l: FantasyForecastLine) -> String {
        var s = String(format: "%.1f pts · %.1f reb · %.1f ast", l.pts, l.reb, l.ast)
        if let fp = l.fp { s += String(format: " · %.1f fp", fp) }
        return s
    }

    private func gradeBadge(_ letter: String) -> some View {
        Text(letter)
            .font(.headline.bold())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    // MARK: Roster card (slotted: Lineup / Bench / IR)

    @ViewBuilder
    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roster").font(.headline)
            if roster.isEmpty {
                Text("No players yet — tap Edit to add.").foregroundStyle(.secondary)
            } else {
                slotSection(.lineup)
                slotSection(.bench)
                slotSection(.ir)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func slotSection(_ slot: FantasySlot) -> some View {
        let here = slugs(in: slot)
        let cap = limits.cap(slot)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(slot.displayName).font(.subheadline.bold())
                Text("\(here.count)/\(cap)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(here.count > cap ? .red : .secondary)
                Spacer()
            }
            .padding(.top, 4)
            if here.isEmpty {
                Text("Empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(here, id: \.self) { rosterRow($0, slot: slot) }
            }
        }
    }

    @ViewBuilder
    private func rosterRow(_ slug: String, slot: FantasySlot) -> some View {
        HStack(spacing: 12) {
            if let p = playerBySlug[slug] {
                NavigationLink(value: p) {
                    HStack(spacing: 12) {
                        HeadshotImage(slug: p.slug, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline.bold())
                            Text("\(p.teamId) · \(p.position)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            } else {
                HeadshotImage(slug: slug, size: 40)                 // graceful placeholder headshot
                Text(slug).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            slotMenu(slug, current: slot)
        }
    }

    /// Per-player slot mover. Full lineup/IR targets are disabled, but "Move to
    /// Bench" is ALWAYS enabled — bench is the model's designated overflow bucket
    /// (its badge turns red when over cap), which keeps a full roster rearrangeable:
    /// demote to bench first (auto-fill promotes the next player into the freed
    /// slot), then move the bench player up once the target has room. Disabling
    /// everything at cap would deadlock a standard 10/3/1 full roster.
    @ViewBuilder
    private func slotMenu(_ slug: String, current: FantasySlot) -> some View {
        Menu {
            ForEach(FantasySlot.allCases) { target in
                if target != current {
                    Button("Move to \(target.displayName)") {
                        fantasyTeamStore.setSlot(slug, in: teamId, to: target)
                    }
                    .disabled(target != .bench
                              && slugs(in: target).count >= limits.cap(target))
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Category-profile card

    @ViewBuilder
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: resolved.first) {
            case .collectionEmpty:
                Text("Value above replacement").font(.headline)
                Text("Fantasy values not available yet.").foregroundStyle(.secondary)
            default:
                profileBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var profileBody: some View {
        let format = appSettings.fantasyFormat
        Text("Value above replacement").font(.headline)
        if resolved.isEmpty {
            Text("Add players to see this team's profile.").foregroundStyle(.secondary)
        } else {
            valueRow(format: format)
            if format.isPoints {
                let total = FantasyTeamProfile.fpPerGameTotal(resolved, format: format)
                HStack {
                    Text("Team projected fantasy pts/game").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", total)).monospacedDigit().bold()
                }
            } else {
                let ordered = FantasyTeamProfile.ordered(FantasyTeamProfile.categoryTotals(resolved))
                let strengths = ordered.filter { $0.z >= 0 }
                let weaknesses = ordered.filter { $0.z < 0 }
                if !strengths.isEmpty {
                    Text("Strengths").font(.subheadline.bold()).padding(.top, 4)
                    ForEach(strengths, id: \.label) { CategoryBarRow(label: $0.label, z: $0.z) }
                }
                if !weaknesses.isEmpty {
                    Text("Weaknesses").font(.subheadline.bold()).padding(.top, 4)
                    ForEach(weaknesses, id: \.label) { CategoryBarRow(label: $0.label, z: $0.z) }
                }
            }
        }
    }

    @ViewBuilder
    private func valueRow(format: FantasyFormat) -> some View {
        let sum = FantasySideValue.sum(resolved, meta: fantasyStore.meta,
                                       format: format, dynastyOn: appSettings.dynastyOn)
        HStack {
            Text("Total value above replacement").foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f", sum)).monospacedDigit().bold()
        }
    }
}
