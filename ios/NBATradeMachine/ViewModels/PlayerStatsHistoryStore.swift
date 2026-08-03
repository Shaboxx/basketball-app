import Foundation
import Combine

/// Lazily loads per-player season-history and per-season game-log docs through the
/// `FirestoreReading` seam. Caches fetched values by slug / slug+season so repeated
/// calls to `load(slug:)` or `loadSeason(slug:season:)` never trigger a second fetch.
///
/// Mirrors `FantasyActualsStore` in structure: `@MainActor`, `ObservableObject`,
/// injectable service, `@Published` caches, lazy load-once with idle/failed retry.
@MainActor
final class PlayerStatsHistoryStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}

    // MARK: - Published state

    /// Keyed by canonical slug. `nil` means the doc was missing or failed to decode.
    @Published private(set) var historyBySlug: [String: PlayerSeasonHistory?] = [:]

    /// Keyed by "\(slug)/\(season)". `nil` means the doc was missing or failed to decode.
    @Published private(set) var gameLogBySlugSeason: [String: PlayerGameLogSeason?] = [:]

    // MARK: - Per-key loading phases (so the UI can show a spinner vs. dash vs. data)

    @Published private(set) var historyPhaseBySlug: [String: FantasyPhase] = [:]
    @Published private(set) var seasonPhaseBySlugSeason: [String: FantasyPhase] = [:]

    // MARK: - Dependencies

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    // MARK: - Load season history

    /// Lazily fetches `playerSeasonHistory/{slug}`. Idempotent: a second call while
    /// loading, or after a successful load, is a no-op. Retries after a failed fetch.
    func load(slug: String) async {
        let phase = historyPhaseBySlug[slug, default: .idle]
        guard phase == .idle || phase == .failed else { return }
        historyPhaseBySlug[slug] = .loading
        do {
            let history = try await service.fetchPlayerSeasonHistory(slug: slug)
            historyBySlug[slug] = history
            historyPhaseBySlug[slug] = history != nil ? .loaded : .empty
        } catch {
            historyPhaseBySlug[slug] = .failed
        }
    }

    /// Convenience accessor: canonical-slug lookup (strips periods, lower-case).
    func history(for slug: String) -> PlayerSeasonHistory? {
        historyBySlug[canonicalSlug(slug)] ?? nil
    }

    // MARK: - Load a single game-log season

    /// Lazily fetches `playerGameLogs/{slug}/seasons/{season}`. Idempotent per
    /// (slug, season) pair. Retries after a failed fetch.
    func loadSeason(slug: String, season: String) async {
        let key = cacheKey(slug: slug, season: season)
        let phase = seasonPhaseBySlugSeason[key, default: .idle]
        guard phase == .idle || phase == .failed else { return }
        seasonPhaseBySlugSeason[key] = .loading
        do {
            let doc = try await service.fetchPlayerGameLogSeason(slug: slug, season: season)
            gameLogBySlugSeason[key] = doc
            seasonPhaseBySlugSeason[key] = doc != nil ? .loaded : .empty
        } catch {
            seasonPhaseBySlugSeason[key] = .failed
        }
    }

    /// Convenience accessor for a cached game-log season.
    func gameLogs(slug: String, season: String) -> PlayerGameLogSeason? {
        gameLogBySlugSeason[cacheKey(slug: slug, season: season)] ?? nil
    }

    // MARK: - Helpers

    private func cacheKey(slug: String, season: String) -> String { "\(slug)/\(season)" }

    /// Strips periods (e.g. "jr.") to match the Firestore canonical slug convention
    /// used throughout the app (mirrors `FantasyValueStore.canonicalSlug`).
    private func canonicalSlug(_ slug: String) -> String {
        slug.replacingOccurrences(of: ".", with: "")
    }
}
