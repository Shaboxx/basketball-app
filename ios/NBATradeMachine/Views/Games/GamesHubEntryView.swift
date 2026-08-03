import SwiftUI

/// Entry point for the Games hub. SP3 replaces the placeholder body with GamesHubView.
/// Retains the FooterState injection so the tab scroll behaviour is consistent.
struct GamesHubEntryView: View {
    @EnvironmentObject private var footerState: FooterState

    var body: some View {
        GamesHubView()
            .reportsFooterScroll(footerState)
    }
}
