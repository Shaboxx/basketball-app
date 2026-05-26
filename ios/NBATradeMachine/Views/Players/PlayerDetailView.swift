import SwiftUI

struct PlayerDetailView: View {
    let player: Player

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

                HStack(spacing: 24) {
                    stat("Height", player.heightDisplay)
                    stat("Weight", player.weightLbs.map { "\($0) lb" } ?? "—")
                    stat("Age", player.age().map { String($0) } ?? "—")
                }

                RolesSection(player: player)
                SalarySection(player: player)
                ProjectedContractSection(player: player)
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
            .padding(.top, 4)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

