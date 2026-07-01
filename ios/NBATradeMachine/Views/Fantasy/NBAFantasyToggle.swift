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
            // Both words are laid out; the opaque thumb below covers the INACTIVE one,
            // leaving only the ACTIVE word legible in its own slot.
            HStack(spacing: 0) {
                Text("NBA").frame(width: trackWidth / 2)
                Text("Fantasy").frame(width: trackWidth / 2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            // Opaque thumb sits over the INACTIVE word's slot, hiding it (no word printed
            // on the thumb). NBA active (isFantasy == false) → cover the RIGHT "Fantasy"
            // slot; Fantasy active (isFantasy == true) → cover the LEFT "NBA" slot.
            Capsule()
                .fill(Color.accentColor)
                .frame(width: trackWidth / 2, height: trackHeight)
                .offset(x: isFantasy ? -trackWidth / 4 : trackWidth / 4)
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
