import SwiftUI

struct CapTierBadge: View {
    let tier: LeagueRules.CapTier

    var body: some View {
        Text(tier.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch tier {
        case .underCap: return .green
        case .overCap: return .blue
        case .overTax: return .orange
        case .overFirstApron: return .red
        case .overSecondApron: return .purple
        }
    }
}

struct TeamLogoMark: View {
    let teamId: String
    var size: CGFloat = 44
    var aliasFont: Font = .caption2
    var showsAlias: Bool = true

    @State private var url: URL?

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: placeholder
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: placeholder
                        @unknown default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)

            if showsAlias {
                Text(teamId)
                    .font(aliasFont.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: teamId) {
            url = await StorageService.shared.logoURL(for: teamId)
        }
    }

    private var placeholder: some View {
        Image(systemName: "shield.lefthalf.filled")
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .foregroundStyle(.secondary.opacity(0.5))
    }
}
