import SwiftUI

/// Top-center sliding NBA/Fantasy switch. An opaque thumb capsule sits over the
/// INACTIVE label so only the ACTIVE word (NBA or Fantasy) is legible, sliding to the
/// other side on toggle. Binds the app-wide `appSettings.fantasyModeOn` (inherited
/// from the root injection), so pages transform in place with no reload.
struct NBAFantasyToggle: View {
    @EnvironmentObject var appSettings: AppSettings

    private let trackWidth: CGFloat = 168
    private let trackHeight: CGFloat = 32

    var body: some View {
        let isFantasy = appSettings.fantasyModeOn
        ZStack {
            Capsule().fill(Color(.tertiarySystemFill))
            HStack(spacing: 0) {
                Text("NBA").frame(width: trackWidth / 2)
                Text("Fantasy").frame(width: trackWidth / 2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            // Opaque thumb covers the INACTIVE word; only the ACTIVE word shows on it.
            Capsule()
                .fill(Color.accentColor)
                .frame(width: trackWidth / 2, height: trackHeight)
                .overlay(
                    Text(isFantasy ? "Fantasy" : "NBA")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                )
                .offset(x: isFantasy ? trackWidth / 4 : -trackWidth / 4)
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(.snappy, value: appSettings.fantasyModeOn)
        .contentShape(Capsule())
        .onTapGesture { appSettings.fantasyModeOn.toggle() }
        .accessibilityElement()
        .accessibilityLabel("NBA Fantasy mode")
        .accessibilityValue(isFantasy ? "Fantasy" : "NBA")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NBAFantasyToggle().environmentObject(AppSettings())
}
