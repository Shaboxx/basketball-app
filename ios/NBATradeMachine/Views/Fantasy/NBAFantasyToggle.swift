import SwiftUI

/// Top-center sliding NBA/Fantasy switch, segmented-control style: a WHITE thumb
/// pill slides under the ACTIVE word, which reads in the accent blue; the
/// inactive word stays muted on the gray track. Binds the app-wide
/// `appSettings.fantasyModeOn` (inherited from the root injection), so pages
/// transform in place with no reload.
struct NBAFantasyToggle: View {
    @EnvironmentObject var appSettings: AppSettings

    private let trackWidth: CGFloat = 168
    private let trackHeight: CGFloat = 32

    var body: some View {
        let isFantasy = appSettings.fantasyModeOn
        ZStack {
            Capsule().fill(Color(.tertiarySystemFill))
            // WHITE thumb (UISwitch-style) slides UNDER the ACTIVE word's slot —
            // segmented-control read: the active word sits highlighted on the white
            // pill, the inactive word stays muted on the gray track.
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .frame(width: trackWidth / 2, height: trackHeight)
                .offset(x: isFantasy ? trackWidth / 4 : -trackWidth / 4)
            // Words render ABOVE the thumb: the ACTIVE (revealed) word in accent
            // blue, the inactive one secondary.
            HStack(spacing: 0) {
                Text("NBA")
                    .foregroundStyle(isFantasy ? Color.secondary : Color.accentColor)
                    .frame(width: trackWidth / 2)
                Text("Fantasy")
                    .foregroundStyle(isFantasy ? Color.accentColor : Color.secondary)
                    .frame(width: trackWidth / 2)
            }
            .font(.subheadline.weight(.semibold))
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
