import SwiftUI

struct PlayerDetailView: View {
    let player: Player
    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeadshotImage(slug: player.slug, size: 160)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(player.name).font(.title.bold())
                    Text("\(player.teamId) · \(player.position)")
                        .foregroundStyle(.secondary)
                    chipRow
                }

                HStack(spacing: 20) {
                    stat("Height", player.heightDisplay)
                    stat("Weight", player.weightLbs.map { "\($0) lb" } ?? "—")
                    stat("Age", player.age().map { String($0) } ?? "—")
                    stat("TOT", Player.fmtVal(player.dispTotal))
                    stat("OFF", Player.fmtVal(player.dispOff))
                    stat("DEF", Player.fmtVal(player.dispDef))
                }

                RolesSection(player: player)
                NewsSection(player: player)
                if AppConfig.fantasyEnabled && appSettings.fantasyModeOn {
                    FantasyValueSection(player: player)
                    CategoryBreakdownSection(player: player)
                    FantasyBoxSection(player: player)
                } else {
                    LatentValueSection(player: player)
                    SalarySection(player: player)
                    ProjectedContractSection(player: player)
                }

                AdBanner()   // bottom-of-page banner slot; self-hides when ads are off
            }
            .padding()
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chipRow: some View {
        let tags = player.playerTags
        let expiry = player.contractExpirySeason
        VStack(spacing: 6) {
            if !tags.isEmpty || expiry != nil {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        PlayerChip(
                            label: tag.label,
                            background: tag.background,
                            foreground: tag.foreground
                        )
                    }
                    if let expiry {
                        PlayerChip(
                            label: "Expires \(expiry)",
                            background: .expiryChip,
                            foreground: .black
                        )
                    }
                }
            }
            profileLabelRow
        }
        .padding(.top, 4)
    }

    /// Dynamic best-3 descriptive profile labels, rendered beneath the existing
    /// status / "Expires" chip row. Uses a subtle neutral chip style so they
    /// read as descriptive labels rather than status badges.
    @ViewBuilder
    private var profileLabelRow: some View {
        let labels = PlayerProfileLabels.labels(for: player, norms: normsVM.norms)
        if !labels.isEmpty {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    PlayerChip(
                        label: label.text,
                        background: Color(.tertiarySystemFill),
                        foreground: .primary
                    )
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

