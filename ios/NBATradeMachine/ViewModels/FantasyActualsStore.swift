import Foundation
import Combine

/// Loads the whole `fantasyActuals` collection (+ `_meta`) once and serves per-slug
/// lookups, keyed by canonical (period-stripped) slug. Mirrors `FantasyValueStore` — the
/// load-once guard keeps the productions map SYNCHRONOUS (no async in the detail view).
@MainActor
final class FantasyActualsStore: ObservableObject {
    @Published private(set) var actualsBySlug: [String: FantasyActuals] = [:]
    @Published private(set) var meta: FantasyActualsMeta?
    @Published private(set) var phase: FantasyPhase = .idle

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        // Load-once, but retry after a failed fetch (see FantasyValueStore) — lazy loading
        // defers the first fetch to the fantasy toggle, so failures must be recoverable.
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let (a, m) = try await service.fetchFantasyActuals()
            actualsBySlug = a; meta = m
            phase = a.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed
        }
    }

    func actuals(for slug: String) -> FantasyActuals? {
        actualsBySlug[FantasyValueStore.canonicalSlug(slug)]
    }

    /// The active season the aggregate was computed for (from `_meta`), used to
    /// season-filter the source so a rollover straggler can't leak into standings.
    /// Equals `calendarVM.statsSeason` in steady state; authoritative here because
    /// calendarVM is not reachable at the detail-view call site (see §1.3).
    var season: String { meta?.season ?? FirestoreService.fallbackSeason }
}
