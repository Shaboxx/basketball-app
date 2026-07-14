import Foundation
import Combine

/// Loads the whole `playerShots` collection once, keyed by canonical slug. Reuses the
/// app-wide FantasyPhase + FantasyValueStore.canonicalSlug (period-stripped ids).
@MainActor
final class PlayerShotStore: ObservableObject {
    @Published private(set) var charts: [String: PlayerShotChart] = [:]
    @Published private(set) var phase: FantasyPhase = .idle
    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let (c, _) = try await service.fetchPlayerShots()
            charts = c
            phase = c.isEmpty ? .empty : .loaded
        } catch { phase = .failed }
    }
    func chart(for slug: String) -> PlayerShotChart? {
        charts[FantasyValueStore.canonicalSlug(slug)]
    }
}
