import Foundation
import Combine

@MainActor
final class PlayersViewModel: ObservableObject {
    @Published var players: [Player] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard players.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await FirestoreService.shared.fetchPlayers()
            self.players = p.sorted { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filtered: [Player] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return players }
        return players.filter { $0.name.lowercased().contains(q) }
    }
}
