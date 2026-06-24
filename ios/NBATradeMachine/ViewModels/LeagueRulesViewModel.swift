import Foundation
import Combine

@MainActor
final class LeagueRulesViewModel: ObservableObject {
    @Published var rules: LeagueRules?

    func load(season: String = FirestoreService.fallbackSeason) async {
        guard rules == nil else { return }
        rules = try? await FirestoreService.shared.fetchLeagueRules(season: season)
    }
}
