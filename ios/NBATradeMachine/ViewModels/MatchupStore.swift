import Foundation
import Combine

/// Loads the whole `matchups` collection once, keyed by canonical slug.
@MainActor
final class MatchupStore: ObservableObject {
    /// App-wide singleton — see PlayerShotStore.shared for why the matchup card consumes
    /// this directly instead of via @EnvironmentObject (crash-proof across nav boundaries).
    static let shared = MatchupStore()
    @Published private(set) var matchups: [String: Matchup] = [:]
    @Published private(set) var phase: FantasyPhase = .idle
    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let m = try await service.fetchMatchups()
            matchups = m
            phase = m.isEmpty ? .empty : .loaded
        } catch { phase = .failed }
    }
    func matchup(for slug: String) -> Matchup? {
        matchups[FantasyValueStore.canonicalSlug(slug)]
    }
}
