import Foundation

/// Errors surfaced to the UI. `notDeployed` is the expected pre-deploy state
/// (the Cloud Function isn't live yet) and reads as "not available yet".
nonisolated enum AdvisorError: Error, Equatable {
    case notDeployed
    case network(String)
    case server(String)
    case decoding(String)
}

/// The seam the front end depends on. Live = FirebaseAdvisorService; tests/previews = MockAdvisorService.
protocol AdvisorService: Sendable {
    nonisolated func requestAdvice(team: String, goal: String, untouchables: [String],
                                   constraints: String?, teamSet: [String],
                                   forceRefresh: Bool) async throws -> AdvisorResponse
}

/// Canned backend for previews + unit tests. No Firebase.
nonisolated struct MockAdvisorService: AdvisorService {
    let result: Result<AdvisorResponse, AdvisorError>

    init(result: Result<AdvisorResponse, AdvisorError> = .success(MockAdvisorService.defaultResponse)) {
        self.result = result
    }

    nonisolated func requestAdvice(team: String, goal: String, untouchables: [String],
                                   constraints: String?, teamSet: [String],
                                   forceRefresh: Bool) async throws -> AdvisorResponse {
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    static let defaultResponse = AdvisorResponse(
        summary: "Here is one option that fits your cap.",
        proposals: [
            AdvisorProposal(
                label: "Add a stretch big",
                moves: [AdvisorMove(playerId: "incoming-big", fromTeam: "ATL", toTeam: "BOS"),
                        AdvisorMove(playerId: "outgoing-wing", fromTeam: "BOS", toTeam: "ATL")],
                legal: true,
                rationale: "Adds floor spacing at the 5 while matching salary.",
                tradeoffs: "Thins perimeter depth.",
                salaryBreakdown: nil)
        ])
}
