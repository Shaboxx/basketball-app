import Foundation
import Combine

@MainActor
final class LeagueRulesViewModel: ObservableObject {
    @Published var rules: LeagueRules?

    func load(season: String = FirestoreService.fallbackSeason) async {
        guard rules == nil else { return }
        await reload(season: season)
    }

    func reload(season: String = FirestoreService.fallbackSeason) async {
        // Keep last-known-good on a failed/missing fetch (a foreground-refresh network
        // blip must not blank already-loaded rules).
        if let r = try? await FirestoreService.shared.fetchLeagueRules(season: season) {
            rules = r
        }
    }
}
