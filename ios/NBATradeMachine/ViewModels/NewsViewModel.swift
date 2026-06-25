import Foundation
import Combine

/// Loads a player's news once per slug. Any fetch error (network, decode, or a
/// not-yet-deployed composite index) collapses to an empty list, so the News
/// section simply hides rather than erroring.
@MainActor
final class NewsViewModel: ObservableObject {
    @Published var items: [NewsItem] = []
    @Published var isLoading = false
    private var loadedSlug: String?

    func load(for slug: String) async {
        guard loadedSlug != slug else { return }
        loadedSlug = slug
        isLoading = true
        defer { isLoading = false }
        items = (try? await FirestoreService.shared.fetchNews(for: slug, limit: 5)) ?? []
    }
}
