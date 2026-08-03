import Foundation
import Combine

/// Loads a player's news once per slug. Any fetch error (network, decode, or a
/// not-yet-deployed composite index) collapses to an empty list, so the News
/// section simply hides rather than erroring.
@MainActor
final class NewsViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var items: [NewsItem] = []
    private var loadedSlug: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load(for slug: String) async {
        guard loadedSlug != slug else { return }   // skip a redundant refetch of the same player
        loadedSlug = slug
        items = (try? await service.fetchNews(for: slug, limit: 5)) ?? []
    }
}
