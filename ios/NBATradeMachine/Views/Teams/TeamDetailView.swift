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

            rosterValueSection(roster: roster)
            teamLeadersSection(roster: roster)

            Section("Depth Chart") {
                TeamDepthChartView(roster: roster)
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
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.display(p.currentSalary))
                                    .font(.caption.monospacedDigit())
                                if let lv = p.latentValue,
                                   (lv.thetaZOff != nil || lv.thetaZDef != nil) {
                                    Text(rosterRowSigma(lv))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
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

    /// Summary band: sum of OFF/DEF σ across the roster (incoming-style
    /// rollup). Hidden when no player on the roster has Rev-2 z fields yet —
    /// avoids showing 0.00 for the handful of teams whose roster still has
    /// only Tier-A docs.
    @ViewBuilder
    private func rosterValueSection(roster: [Player]) -> some View {
        let (off, def, rated, total) = rosterValueRollup(roster)
        if rated > 0 {
            Section("Roster Latent Value") {
                HStack(spacing: 16) {
                    rollupCell("OFF Σσ", signed(off))
                    rollupCell("DEF Σσ", signed(def))
                    rollupCell("Coverage", "\(rated) / \(total)")
                }
            }
        }
    }

    private func rollupCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rosterValueRollup(_ roster: [Player]) -> (off: Double, def: Double, rated: Int, total: Int) {
        var off = 0.0
        var def = 0.0
        var rated = 0
        for p in roster {
            guard let lv = p.latentValue else { continue }
            let o = lv.thetaZOff
            let d = lv.thetaZDef
            guard o != nil || d != nil else { continue }
            off += o ?? 0
            def += d ?? 0
            rated += 1
        }
        return (off, def, rated, roster.count)
    }

    /// Top-3 OFF and top-3 DEF on the roster by Rev-2 σ. Lets you eyeball
    /// who actually carries each side of the ball. Section auto-hides when
    /// fewer than 2 rated players exist on the roster — under 2 it's not a
    /// "leaderboard," it's just one name.
    @ViewBuilder
    private func teamLeadersSection(roster: [Player]) -> some View {
        let rated = roster.filter { p in
            guard let lv = p.latentValue else { return false }
            return lv.thetaZOff != nil || lv.thetaZDef != nil
        }
        if rated.count >= 2 {
            let topOff = rated
                .compactMap { p -> (Player, Double)? in
                    guard let z = p.latentValue?.thetaZOff else { return nil }
                    return (p, z)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
            let topDef = rated
                .compactMap { p -> (Player, Double)? in
                    guard let z = p.latentValue?.thetaZDef else { return nil }
                    return (p, z)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
            Section("Team Leaders") {
                leaderColumn(title: "OFF", items: Array(topOff))
                leaderColumn(title: "DEF", items: Array(topDef))
            }
        }
    }

    @ViewBuilder
    private func leaderColumn(title: String, items: [(Player, Double)]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.0.id) { (player, value) in
                    NavigationLink(value: player) {
                        HStack {
                            Text(player.name).font(.subheadline)
                            Spacer()
                            Text(String(format: "%+.2fσ", value))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(value >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rosterRowSigma(_ lv: LatentValue) -> String {
        let o = lv.thetaZOff.map { String(format: "%+.2f", $0) } ?? "—"
        let d = lv.thetaZDef.map { String(format: "%+.2f", $0) } ?? "—"
        return "OFF \(o) · DEF \(d)"
    }

    private func signed(_ v: Double) -> String {
        String(format: "%+.2f", v)
    }
}
