import Foundation
import Combine

@MainActor
final class LeagueRulesViewModel: ObservableObject {
    @Published var rules: LeagueRules?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load(season: String = FirestoreService.fallbackSeason) async {
        guard rules == nil else { return }
        await reload(season: season)
    }

    func reload(season: String = FirestoreService.fallbackSeason) async {
        // Keep last-known-good on a failed/missing fetch (a foreground-refresh network
        // blip must not blank already-loaded rules).
        if let r = try? await service.fetchLeagueRules(season: season) {
            rules = r
        }
    }
}
