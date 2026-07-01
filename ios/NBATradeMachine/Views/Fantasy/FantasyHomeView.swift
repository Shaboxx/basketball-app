import SwiftUI

/// The fantasy Teams surface's Teams | Leagues segmented container. Rather than modify the
/// shipped `FantasyTeamsListView` (which owns its own NavigationStack), this thin container
/// hosts the segmented `Picker` above whichever child renders. `ContentView.contentArea`'s
/// `.teams` case renders this instead of `FantasyTeamsListView()` in fantasy mode — a
/// one-line swap; `FantasyTeamsListView` is reused unmodified.
struct FantasyHomeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case teams = "Teams", leagues = "Leagues"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .teams

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 8)

            switch tab {
            case .teams:   FantasyTeamsListView()      // shipped, unmodified (owns its NavigationStack)
            case .leagues: FantasyLeaguesListView()    // NEW (owns its NavigationStack)
            }
        }
    }
}
