import Foundation
import Combine

/// League-wide news feed. `load()` fetches once; `reload()` force-refreshes
/// (pull-to-refresh / foreground). Holds the Top/Newest sort + the Hot Players
/// ranking. A failed reload keeps existing items, surfacing an error only when empty.
@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published var items: [NewsItem] = []
    @Published var hotPlayers: [HotPlayer] = []
    @Published var sort: NewsSort = .top
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Hot players the user has tapped to filter the feed. Empty -> full feed.
    @Published private(set) var selectedSlugs: Set<String> = []

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
        guard items.isEmpty else { return }
        await reload()
    }

    func setSort(_ newSort: NewsSort) async {
        guard newSort != sort else { return }
        sort = newSort
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.fetchLeagueNews(sort: sort, limit: 30)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Hot Players is best-effort: a failure here must not blank the feed.
        hotPlayers = (try? await service.fetchHotPlayers()) ?? hotPlayers
    }
}
