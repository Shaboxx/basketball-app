import Foundation
import Combine

@MainActor
final class PicksViewModel: ObservableObject {
    @Published var picksByTeamId: [String: [Pick]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard picksByTeamId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            picksByTeamId = try await FirestoreService.shared.fetchAllTeamPicks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func picks(for teamId: String) -> [Pick] {
        picksByTeamId[teamId] ?? []
    }
}
