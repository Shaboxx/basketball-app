import SwiftUI

/// The fantasy Teams surface's Teams | Leagues segmented container. Rather than modify the
/// shipped `FantasyTeamsListView` (which owns its own NavigationStack), this thin container
/// hosts the segmented `Picker` above whichever child renders. `ContentView.contentArea`'s
/// `.teams` case renders this instead of `FantasyTeamsListView()` in fantasy mode — a
/// one-line swap; `FantasyTeamsListView` is reused unmodified.
struct FantasyHomeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case teams = "Teams", leagues = "Leagues", pickem = "Pick'em"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .teams

    /// Pick'em only appears when its flag is on (the enum case can't be conditional).
    private var visibleTabs: [Tab] { Tab.allCases.filter { $0 != .pickem || PickemGate.shouldShow() } }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(visibleTabs) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 8)

            switch tab {
            case .teams:   FantasyTeamsListView()      // shipped, unmodified (owns its NavigationStack)
            case .leagues: LeaguesTab()                // Local | Hosted sub-segment (hosted flag-gated)
            case .pickem:  PickemHomeView()            // owns its NavigationStack + PickemStore
            }
        }
    }
}

/// The Leagues tab. When hosted leagues are off (default), it renders the shipped local
/// `FantasyLeaguesListView` directly. When `hostedLeaguesEnabled`, it layers a `Local | Hosted`
/// sub-segment above it so online leagues live beside — never replacing — local ones.
private struct LeaguesTab: View {
    enum Scope: String, CaseIterable, Identifiable { case local = "Local", hosted = "Hosted"; var id: String { rawValue } }
    @State private var scope: Scope = .local

    var body: some View {
        if HostedLeaguesGate.shouldShow() {
            VStack(spacing: 0) {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.bottom, 8)

                switch scope {
                case .local:  FantasyLeaguesListView()   // shipped, unmodified (owns its NavigationStack)
                case .hosted: HostedLeaguesListView()     // owns its NavigationStack
                }
            }
        } else {
            FantasyLeaguesListView()
        }
    }
}
