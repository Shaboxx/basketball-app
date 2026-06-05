import Foundation

/// Decoded from the `runTradeAdvisor` callable payload `{summary, proposals}`.
/// The server-side legality backstop has already set `legal`/`salary_breakdown`;
/// the client only displays them and never decides CBA legality itself.
///
/// Pure data models — explicitly nonisolated so they can be decoded and read
/// from any concurrency context (not bound to the app-wide MainActor default).
nonisolated struct AdvisorResponse: Codable, Equatable {
    let summary: String
    let proposals: [AdvisorProposal]
}

nonisolated struct AdvisorProposal: Codable, Equatable, Identifiable {
    var id: String { label }
    let label: String
    let moves: [AdvisorMove]
    let legal: Bool
    let rationale: String
    let tradeoffs: String
    let salaryBreakdown: [String: ProposalTeamBreakdown]?   // keyed by tricode

    enum CodingKeys: String, CodingKey {
        case label, moves, legal, rationale, tradeoffs
        case salaryBreakdown = "salary_breakdown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moves = try c.decode([AdvisorMove].self, forKey: .moves)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Proposal"
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        tradeoffs = try c.decodeIfPresent(String.self, forKey: .tradeoffs) ?? ""
        legal = try c.decodeIfPresent(Bool.self, forKey: .legal) ?? false
        salaryBreakdown = try c.decodeIfPresent([String: ProposalTeamBreakdown].self, forKey: .salaryBreakdown)
    }

    init(label: String, moves: [AdvisorMove], legal: Bool, rationale: String, tradeoffs: String, salaryBreakdown: [String: ProposalTeamBreakdown]?) {
        self.label = label
        self.moves = moves
        self.legal = legal
        self.rationale = rationale
        self.tradeoffs = tradeoffs
        self.salaryBreakdown = salaryBreakdown
    }
}

nonisolated struct AdvisorMove: Codable, Equatable, Identifiable {
    var id: String { "\(playerId)->\(toTeam)" }
    let playerId: String   // canonical slug
    let fromTeam: String   // tricode
    let toTeam: String     // tricode

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case fromTeam = "from_team"
        case toTeam = "to_team"
    }
}

nonisolated struct ProposalTeamBreakdown: Codable, Equatable {
    let outgoing: Int?
    let incoming: Int?
    let postTradeSalary: Int?
    let tier: String?
    let matched: Bool?

    enum CodingKeys: String, CodingKey {
        case outgoing, incoming, tier, matched
        case postTradeSalary = "post_trade_salary"
    }
}
