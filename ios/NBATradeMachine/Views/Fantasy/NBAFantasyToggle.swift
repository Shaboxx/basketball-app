import SwiftUI

/// Top-center sliding NBA/Fantasy switch, segmented-control style: a WHITE thumb
/// pill slides under the ACTIVE word, which reads in the accent blue; the
/// inactive word stays muted on the gray track. Binds the app-wide
/// `appSettings.fantasyModeOn` (inherited from the root injection), so pages
/// transform in place with no reload.
struct NBAFantasyToggle: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        // Light mode: match the prominent Trade button — accent-filled thumb, white active label.
        SlidingSwitch(isRight: $appSettings.fantasyModeOn,
                      accessibilityName: "NBA Fantasy mode",
                      leftName: "NBA", rightName: "Fantasy",
                      dayThumbColor: .accentColor, dayActiveColor: .white) {
            Text("NBA")
        } right: {
            Text("Fantasy")
        }
    }
}

#Preview {
    NBAFantasyToggle().environmentObject(AppSettings())
}
