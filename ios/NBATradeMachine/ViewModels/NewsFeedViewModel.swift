import Foundation
import Combine

/// League-wide news feed. `load()` fetches once; `reload()` force-refreshes
/// (pull-to-refresh / foreground). Holds the Top/Newest sort + the Hot Players
/// ranking. A failed reload keeps existing items, surfacing an error only when empty.
@MainActor
final class NewsFeedViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var items: [NewsItem] = []
    @Published var hotPlayers: [HotPlayer] = []
    @Published var sort: NewsSort = .top
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Bumped when a refresh fails while the feed is ALREADY loaded — drives a transient banner
    /// instead of wiping the feed.
    @Published private(set) var refreshFailures = 0

    /// Hot players the user has tapped to filter the feed. Empty -> full feed.
    @Published private(set) var selectedSlugs: Set<String> = []

    // MARK: - Snapshot

    /// UserDefaults key for the top-of-feed snapshot (S1).
    static let snapshotKey = "NewsFeedSnapshot"
    /// Maximum items persisted in the snapshot — bounds UserDefaults size.
    static let snapshotCap = 15

    /// Persist up to `snapshotCap` items so the next cold-start can paint instantly.
    /// Silently swallows encode errors (best-effort).
    static func saveSnapshot(_ items: [NewsItem]) {
        guard let data = try? JSONEncoder().encode(Array(items.prefix(snapshotCap))) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    /// Restore the last-saved snapshot. Returns [] when absent or undecodable.
    static func loadSnapshot() -> [NewsItem] {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let items = try? JSONDecoder().decode([NewsItem].self, from: data) else { return [] }
        return items
    }

    // MARK: - State

    /// True once `reload()` has been called at least once; prevents `load()` from
    /// re-entering on subsequent calls while preserving the snapshot-paint path.
    private var didFetch = false

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func toggleSelection(_ slug: String) {
        if selectedSlugs.contains(slug) { selectedSlugs.remove(slug) }
        else { selectedSlugs.insert(slug) }
    }

    func isSelected(_ slug: String) -> Bool { selectedSlugs.contains(slug) }

    /// The feed actually rendered: full list when nothing is selected, else only items
    /// mentioning a selected player, most-relevant first.
    var displayedItems: [NewsItem] { Self.display(items, selected: selectedSlugs) }

    // MARK: - Dedupe

    /// A story identity for de-duplication: the title reduced to lowercase
    /// alphanumeric words. Collapses punctuation / smart-quote / casing differences
    /// so the same headline from two sources (e.g. a direct feed AND a Google-News
    /// wrapper) — or a stale doc left behind under a drifted clusterId — maps to one key.
    nonisolated static func storyKey(_ title: String) -> String {
        let scalars = title.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Collapse items that are the same story (identical `storyKey`), keeping the FIRST
    /// occurrence — the input is already ranked (hotness for Top, recency for Newest), so
    /// the first copy is the best-ranked one. Order-preserving. Empty-title items (which
    /// shouldn't exist) are never merged together. This is the client-side safety net so
    /// duplicate docs never render side by side even before the Firestore dedupe runs.
    nonisolated static func dedupe(_ items: [NewsItem]) -> [NewsItem] {
        var seen = Set<String>()
        var result: [NewsItem] = []
        result.reserveCapacity(items.count)
        for item in items {
            let key = storyKey(item.title)
            if key.isEmpty { result.append(item); continue }
            if seen.insert(key).inserted { result.append(item) }
        }
        return result
    }

    /// True when a hot player is selected but the feed has no matching articles — the
    /// view uses this to trigger the per-player fallback fetch (S2).
    var displayedItemsEmpty: Bool { displayedItems.isEmpty && !selectedSlugs.isEmpty }

    /// Pure relevance filter. No selection -> input order. Otherwise keep items whose
    /// playerSlugs intersect `selected`, ordered (overlap desc, hotnessScore desc,
    /// publishedAt desc).
    nonisolated static func display(_ items: [NewsItem], selected: Set<String>) -> [NewsItem] {
        guard !selected.isEmpty else { return items }
        return items
            .filter { !selected.isDisjoint(with: $0.playerSlugs) }
            .sorted { a, b in
                let oa = selected.intersection(a.playerSlugs).count
                let ob = selected.intersection(b.playerSlugs).count
                if oa != ob { return oa > ob }
                let ha = a.hotnessScore ?? 0, hb = b.hotnessScore ?? 0
                if ha != hb { return ha > hb }
                // `publishedAt` is canonical fixed-width UTC ("…Z"), so a lexical
                // descending compare equals chronological (same assumption as
                // FirestoreService.filterNews).
                return a.publishedAt > b.publishedAt
            }
    }

    func load() async {
        // Paint the snapshot synchronously (zero network wait) on the very first call.
        if !didFetch {
            let snap = Self.loadSnapshot()
            if !snap.isEmpty { items = Self.dedupe(snap) }
        }
        guard !didFetch else { return }
        await reload()
    }

    func setSort(_ newSort: NewsSort) async {
        guard newSort != sort else { return }
        sort = newSort
        await reload()
    }

    func reload() async {
        didFetch = true
        isLoading = true
        defer { isLoading = false }
        do {
            // Dedupe defensively: the news collection can hold duplicate docs for one
            // story (stale drifted clusterIds, or the same article from two feeds).
            items = Self.dedupe(try await service.fetchLeagueNews(sort: sort, limit: 30))
            // Persist the fresh top-15 so the next cold-start paints instantly.
            Self.saveSnapshot(items)
            errorMessage = nil
        } catch {
            // Full-screen error only with NOTHING to show; otherwise keep the loaded feed and
            // surface a transient "couldn't refresh" banner (non-destructive, Apple News style).
            if items.isEmpty { errorMessage = FriendlyError.message(error) } else { refreshFailures += 1 }
        }
        // Hot Players is best-effort: a failure here must not blank the feed.
        hotPlayers = (try? await service.fetchHotPlayers()) ?? hotPlayers
    }

    // MARK: - S2: Hot-player fallback coverage

    /// When a single hot player is selected but the loaded feed has no matching articles,
    /// fetch that player's own articles and merge them in (no duplicates, no reorder of
    /// existing items). Multi-select: no-op (union results are already shown).
    func fetchPlayerFallback(slug: String) async {
        guard selectedSlugs == [slug] else { return }
        guard let fetched = try? await service.fetchNews(for: slug, limit: 10),
              !fetched.isEmpty else { return }
        let existingIds = Set(items.map(\.id))
        let novel = fetched.filter { !existingIds.contains($0.id) }
        guard !novel.isEmpty else { return }
        // Dedupe by story so a fallback article that duplicates a shown headline
        // (different doc id, same title) isn't appended twice.
        items = Self.dedupe(items + novel)
    }
}
