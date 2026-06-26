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

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

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
