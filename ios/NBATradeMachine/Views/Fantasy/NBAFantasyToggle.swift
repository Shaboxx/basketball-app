import SwiftUI

/// Top-center sliding NBA/Fantasy switch, segmented-control style: a WHITE thumb
/// pill slides under the ACTIVE word, which reads in the accent blue; the
/// inactive word stays muted on the gray track. Binds the app-wide
/// `appSettings.fantasyModeOn` (inherited from the root injection), so pages
/// transform in place with no reload.
struct NBAFantasyToggle: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        SlidingSwitch(isRight: $appSettings.fantasyModeOn,
                      accessibilityName: "NBA Fantasy mode",
                      leftName: "NBA", rightName: "Fantasy") {
            Text("NBA")
        } right: {
            Text("Fantasy")
        }
    }
}

#Preview {
    NBAFantasyToggle().environmentObject(AppSettings())
}
