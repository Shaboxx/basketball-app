import Foundation
import Combine

/// League-wide news feed. `load()` fetches once; `reload()` force-refreshes
/// (pull-to-refresh / foreground). A failed reload keeps the existing items and
/// only surfaces an error when the list is still empty.
@MainActor
final class NewsFeedViewModel: ObservableObject {
    @Published var items: [NewsItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await FirestoreService.shared.fetchLeagueNews(limit: 30)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
