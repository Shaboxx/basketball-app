import Foundation
import Combine

/// Loads the singleton lineup league-norms doc (`leagueNorms/2025-26`) once and
/// holds it for the depth-chart breakdown sheets. When the doc is missing or
/// fails to load, `norms` stays nil and the breakdown view shows "unavailable"
/// rather than crashing.
@MainActor
final class LeagueNormsViewModel: ObservableObject {
    @Published var norms: LeagueNorms?

    func load() async {
        guard norms == nil else { return }
        norms = try? await FirestoreService.shared.fetchLeagueNorms()
    }
}
