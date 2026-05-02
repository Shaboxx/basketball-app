import SwiftUI

struct TradeTabBar: View {
    let teams: [Team]
    @Binding var selection: String
    let canAddTeam: Bool
    let onAddTap: () -> Void

    private let tabHeight: CGFloat = 56
    private let selectedHeight: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let unitCount = max(Double(teams.count - 1) + 2.0 + (canAddTeam ? 1.0 : 0.0), 1.0)
            let unit = geo.size.width / unitCount
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(teams) { team in
                    let isSelected = team.teamId == selection
                    teamTab(team: team, isSelected: isSelected)
                        .frame(width: isSelected ? unit * 2 : unit, height: isSelected ? selectedHeight : tabHeight)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) { selection = team.teamId }
                        }
                }
                if canAddTeam {
                    addTab()
                        .frame(width: unit, height: tabHeight)
                        .onTapGesture { onAddTap() }
                }
            }
        }
        .frame(height: selectedHeight)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(Color(.systemGroupedBackground))
    }

    private func teamTab(team: Team, isSelected: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12
        )
        let bg: Color = isSelected ? Color(.systemBackground) : Color(.secondarySystemBackground)
        let logoSize: CGFloat = isSelected ? 34 : 26
        let aliasFont: Font = isSelected ? .caption.bold() : .caption2.weight(.semibold)
        return TeamLogoMark(teamId: team.teamId, size: logoSize, aliasFont: aliasFont)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 4)
            .background(bg, in: shape)
            .overlay(shape.stroke(Color.black.opacity(0.05), lineWidth: 0.5))
    }

    private func addTab() -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12
        )
        return Image(systemName: "plus")
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.18), in: shape)
            .overlay(shape.stroke(Color.black.opacity(0.05), lineWidth: 0.5))
    }
}
