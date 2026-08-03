import SwiftUI

/// Placeholder for the Games hub (SP3 replaces the body). Ships now so the
/// footer's Games cell has a real destination. Reports scroll to the footer so
/// the expand/collapse bar behaves like the other tabs.
struct GamesHubEntryView: View {
    @EnvironmentObject private var footerState: FooterState

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Games")
                    .font(.headline)
                Text("Scores and matchups are coming soon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .reportsFooterScroll(footerState)
    }
}
