import SwiftUI

/// One saved team: roster rows (tap → PlayerDetailView) + a category-profile card
/// ("Value above replacement", or the points fp/game total). Reads the store +
/// FantasyTeamProfile / FantasySideValue.
struct FantasyTeamDetailView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings

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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
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

    // MARK: Roster card

    @ViewBuilder
    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roster").font(.headline)
            let slugs = team?.playerSlugs ?? []
            if slugs.isEmpty {
                Text("No players yet — tap Edit to add.").foregroundStyle(.secondary)
            } else {
                ForEach(slugs, id: \.self) { slug in
                    rosterRow(slug)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func rosterRow(_ slug: String) -> some View {
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
            HStack(spacing: 12) {
                HeadshotImage(slug: slug, size: 40)                 // graceful placeholder headshot
                Text(slug).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
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
