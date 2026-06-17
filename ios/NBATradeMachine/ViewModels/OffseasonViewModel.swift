import Foundation
import Combine

@MainActor
final class OffseasonViewModel: ObservableObject {

    enum Phase {
        case idle
        case loading
        case empty                      // no simulation has been run yet
        case loaded(OffseasonSummary)
        case failed(String)
    }
    enum TeamPhase {
        case idle
        case loading
        case empty
        case loaded(TeamOffseason)
        case failed(String)
    }

    /// Injected backend (live in app, mock in tests/previews).
    var service: any OffseasonService

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var teamPhase: TeamPhase = .idle

    init(service: any OffseasonService) { self.service = service }

    func load() async {
        phase = .loading
        do {
            if let summary = try await service.fetchSummary() {
                phase = .loaded(summary)
            } else {
                phase = .empty
            }
        } catch {
            phase = .failed("Couldn't load the offseason simulation. Please try again.")
        }
    }

    func loadTeam(_ tricode: String) async {
        teamPhase = .loading
        do {
            if let team = try await service.fetchTeam(tricode) {
                teamPhase = .loaded(team)
            } else {
                teamPhase = .empty
            }
        } catch {
            teamPhase = .failed("Couldn't load \(tricode)'s offseason.")
        }
    }
}
