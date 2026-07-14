import Foundation
import Combine

/// Loads the whole `playerShots` collection once, keyed by canonical slug. Reuses the
/// app-wide FantasyPhase + FantasyValueStore.canonicalSlug (period-stripped ids).
@MainActor
final class PlayerShotStore: ObservableObject {
    /// App-wide singleton. Consumed directly (not via @EnvironmentObject) so the
    /// player-page card can't crash on a navigation boundary that didn't re-inject the
    /// store — SwiftUI environment does NOT propagate across sheet / fullScreenCover /
    /// navigationDestination, and PlayerDetailView is presented from many such sites.
    /// Mirrors FirestoreService.shared; this is a genuine load-once read cache.
    static let shared = PlayerShotStore()
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
