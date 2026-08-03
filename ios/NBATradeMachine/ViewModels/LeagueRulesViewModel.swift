import Foundation
import Combine

@MainActor
final class LeagueRulesViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
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
