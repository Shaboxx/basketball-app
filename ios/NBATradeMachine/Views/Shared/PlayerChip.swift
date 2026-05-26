import SwiftUI

/// Capsule pill used by PlayerDetailView's chip row and PlayerSelectionRow.
struct PlayerChip: View {
    let label: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }
}

/// Amber background used by the always-on "Expires <season>" chip.
extension Color {
    static let expiryChip = Color(red: 1.0, green: 0.624, blue: 0.039)
}

#Preview {
    VStack(spacing: 8) {
        PlayerChip(label: "Supermax", background: .purple, foreground: .white)
        PlayerChip(label: "Expires 2026-27", background: .expiryChip, foreground: .black)
        PlayerChip(label: "Expires '26-27", background: .expiryChip, foreground: .black)
    }
    .padding()
}
