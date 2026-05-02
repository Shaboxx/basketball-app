import SwiftUI

struct PlayerSelectionRow: View {
    let player: Player
    let seasonOffset: Int
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    HeadshotImage(slug: player.slug, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.name).font(.subheadline)
                        Text(player.position).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.display(player.salary(forSeasonOffset: seasonOffset)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(player.contractYearsRemaining(from: seasonOffset))y left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink(value: player) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
