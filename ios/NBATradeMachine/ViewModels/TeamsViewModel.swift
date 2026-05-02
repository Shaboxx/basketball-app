import Foundation
import Combine

@MainActor
final class TeamsViewModel: ObservableObject {
    @Published var teams: [Team] = []
    @Published var playersByTeamId: [String: [Player]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        guard teams.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let teamsTask = FirestoreService.shared.fetchTeams()
            async let playersTask = FirestoreService.shared.fetchPlayers()
            let (teams, players) = try await (teamsTask, playersTask)
            self.teams = teams.sorted { $0.fullName < $1.fullName }
            self.playersByTeamId = Dictionary(grouping: players, by: { $0.teamId })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func players(for teamId: String) -> [Player] {
        (playersByTeamId[teamId] ?? []).sorted { $0.currentSalary > $1.currentSalary }
    }

    func totalSalary(for teamId: String) -> Int {
        players(for: teamId).reduce(0) { $0 + $1.currentSalary }
    }
}
