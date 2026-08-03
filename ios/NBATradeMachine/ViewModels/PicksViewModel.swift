import Foundation
import Combine

@MainActor
final class PicksViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var picksByTeamId: [String: [Pick]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard picksByTeamId.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            picksByTeamId = try await service.fetchAllTeamPicks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func picks(for teamId: String) -> [Pick] {
        picksByTeamId[teamId] ?? []
    }
}
