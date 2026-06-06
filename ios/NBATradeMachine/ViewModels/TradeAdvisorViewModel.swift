import Foundation
import Combine

@MainActor
final class TradeAdvisorViewModel: ObservableObject {

    enum Phase {
        case idle
        case loading
        case loaded(AdvisorResponse)
        case failed(String)
    }

    /// Tricode of the team the advice is for (set by the entry point).
    var team: String
    /// Injected backend (live in app, mock in tests/previews). Mutable so a
    /// shared test instance can swap it per case. `any` existential is required
    /// in Swift 6.
    var service: any AdvisorService
    /// Tricodes the advisor may trade among (set by the entry point). >=2 constrains partners.
    var teamSet: [String]

    @Published var goal: String = ""
    @Published var untouchables: [String] = []
    @Published var constraints: String? = nil
    @Published private(set) var phase: Phase = .idle

    init(team: String, service: any AdvisorService, teamSet: [String] = []) {
        self.team = team
        self.service = service
        self.teamSet = teamSet
    }

    var canAsk: Bool {
        if case .loading = phase { return false }
        return !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func ask() async { await run(forceRefresh: false) }
    func refresh() async { await run(forceRefresh: true) }

    private func run(forceRefresh: Bool) async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .loading
        do {
            let resp = try await service.requestAdvice(
                team: team, goal: trimmed, untouchables: untouchables,
                constraints: constraints, teamSet: teamSet, forceRefresh: forceRefresh)
            phase = .loaded(resp)
        } catch let error as AdvisorError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed("Something went wrong. Please try again.")
        }
    }

    /// Test-only reset of the published phase (the shared instance never deinits).
    func resetPhaseForTesting() { phase = .idle }

    private static func message(for error: AdvisorError) -> String {
        switch error {
        case .notDeployed: return "The Trade Advisor isn't available yet."
        case .network(let m): return "Network problem: \(m)"
        case .server(let m): return "The advisor had a problem: \(m)"
        case .decoding: return "Couldn't read the advisor's response."
        }
    }
}
