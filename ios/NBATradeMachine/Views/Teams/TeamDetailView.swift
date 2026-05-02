import SwiftUI

struct TeamDetailView: View {
    let team: Team
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var rulesVM: LeagueRulesViewModel

    var body: some View {
        let roster = teamsVM.players(for: team.teamId)
        let total = teamsVM.totalSalary(for: team.teamId)

        List {
            Section {
                HStack(spacing: 16) {
                    TeamLogoMark(teamId: team.teamId, size: 72, aliasFont: .caption)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(team.fullName).font(.title2.bold())
                        Text("\(team.conference) · \(team.division)").font(.caption).foregroundStyle(.secondary)
                        Text("Record: —").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Roster (\(roster.count))") {
                ForEach(roster) { p in
                    NavigationLink(value: p) {
                        HStack {
                            HeadshotImage(slug: p.slug, size: 36)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.subheadline)
                                Text(p.position).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.display(p.currentSalary)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }

            Section("Total Team Salary") {
                HStack {
                    Text(Money.display(total)).font(.title3.bold().monospacedDigit())
                    Spacer()
                    if let rules = rulesVM.rules {
                        CapTierBadge(tier: rules.tier(for: total))
                    }
                }
            }
        }
        .navigationDestination(for: Player.self) { p in
            PlayerDetailView(player: p)
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
