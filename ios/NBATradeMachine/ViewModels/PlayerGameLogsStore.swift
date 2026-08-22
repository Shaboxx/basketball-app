import Foundation
import Combine

/// Per-slug game-log cache for fantasy weekly scoring.
///
/// Fetches `playerGameLogs/{slug}/seasons/{season}` on demand via the existing
/// `FirestoreReading.fetchPlayerGameLogSeason` seam.  Designed for incremental
/// loading: calling `load(slugs:season:)` multiple times with overlapping sets only
/// fetches slugs that are genuinely missing for the active season.  A season change
/// clears the cache so a rollover never leaks stale data into the new season.
///
/// Concurrency: `@MainActor` — all published state reads are synchronous; the async
/// work is dispatched inside a non-throwing TaskGroup bounded to ~6 parallel fetches.
/// Each per-slug fetch is wrapped in a `Result` so failure attribution is unambiguous.
@MainActor
final class PlayerGameLogsStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}

    // MARK: - Published state

    @Published private(set) var logsBySlug: [String: PlayerGameLogSeason] = [:]
    @Published private(set) var loadedSlugs: Set<String> = []
    @Published private(set) var failedSlugs: Set<String> = []
    @Published private(set) var season: String?

    // MARK: - Private

    private let service: FirestoreReading
    /// Maximum concurrent fetches in a single `load` call.
    private nonisolated let concurrencyLimit = 6

    // MARK: - Init

    init(service: FirestoreReading = FirestoreService.shared) {
        self.service = service
    }

    // MARK: - Public API

    /// Fetch game logs for `slugs` in `season`.
    ///
    /// - Slugs already present in `loadedSlugs` for the same season are skipped.
    /// - A season change clears the entire cache before fetching.
    /// - Per-slug failures are recorded in `failedSlugs`; they do not abort the batch.
    /// - Concurrency is bounded to ~6 parallel Firestore reads.
    func load(slugs: [String], season: String) async {
        // Season change → purge stale cache.
        if self.season != season {
            logsBySlug = [:]
            loadedSlugs = []
            failedSlugs = []
            self.season = season
        }

        // Canonicalise and de-duplicate the requested slugs, skipping already-loaded ones.
        let canonical = slugs.map(FantasyValueStore.canonicalSlug)
        let needed = canonical.filter { !loadedSlugs.contains($0) }
        guard !needed.isEmpty else { return }

        await fetchAll(slugs: needed, season: season)
    }

    /// Retry slugs currently in `failedSlugs` (or a specific subset).
    ///
    /// Clears the requested slugs from `failedSlugs` before re-fetching so a
    /// caller can distinguish "pending retry" from "known failure".
    func retry(slugs: [String]? = nil) async {
        guard let activeSeason = season else { return }
        let canonical = slugs?.map(FantasyValueStore.canonicalSlug) ?? Array(failedSlugs)
        guard !canonical.isEmpty else { return }
        // Remove from failedSlugs so load() will not skip them (they're not in loadedSlugs).
        for slug in canonical { failedSlugs.remove(slug) }
        await load(slugs: canonical, season: activeSeason)
    }

    // MARK: - Private implementation

    /// Non-throwing TaskGroup fetch.  Each per-slug call is wrapped in `Result` so the
    /// group can continue on individual failures and we always know which slug failed.
    private func fetchAll(slugs: [String], season: String) async {
        typealias SlugResult = (slug: String, result: Result<PlayerGameLogSeason?, Error>)
        let limit = concurrencyLimit

        await withTaskGroup(of: SlugResult.self) { [service, season] group in
            var iterator = slugs.makeIterator()
            var inFlight = 0

            // Enqueues a single fetch task for `slug`.
            func addTask(for slug: String) {
                group.addTask {
                    do {
                        let log = try await service.fetchPlayerGameLogSeason(slug: slug, season: season)
                        return (slug, .success(log))
                    } catch {
                        return (slug, .failure(error))
                    }
                }
                inFlight += 1
            }

            // Seed the group with the first `limit` tasks.
            while inFlight < limit, let slug = iterator.next() {
                addTask(for: slug)
            }

            // Drain results and refill to maintain bounded concurrency.
            for await (slug, result) in group {
                // Immediately enqueue the next slug (if any) to keep pipeline full.
                if let next = iterator.next() { addTask(for: next) }

                switch result {
                case .success(let logSeason):
                    if let logSeason { logsBySlug[slug] = logSeason }
                    // Mark loaded even when Firestore returns nil (= no doc for this
                    // season).  That is a *resolved* state, not a fetch failure.
                    loadedSlugs.insert(slug)
                    failedSlugs.remove(slug)
                case .failure:
                    failedSlugs.insert(slug)
                    // Intentionally NOT added to loadedSlugs so a future load() call
                    // will retry this slug.
                }
            }
        }
    }
}
