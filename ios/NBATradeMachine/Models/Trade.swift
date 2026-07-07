import Foundation

struct Trade: Codable {
    static let cashLimit: Int = 8_120_000

    var teams: [Team] = []
    var movements: [PlayerMovement] = []
    var pickMovements: [PickMovement] = []
    var cashSent: [String: Int] = [:]
    var waived: [WaivedContract] = []
    var dismissed: [DismissedPlayer] = []

    mutating func reset() {
        teams.removeAll()
        movements.removeAll()
        pickMovements.removeAll()
        cashSent.removeAll()
        waived.removeAll()
        dismissed.removeAll()
    }

    func incomingPlayerIds(to teamId: String) -> [String] {
        movements.filter { $0.toTeamId == teamId }.map(\.playerId)
    }

    func outgoingPlayerIds(from teamId: String) -> [String] {
        movements.filter { $0.fromTeamId == teamId }.map(\.playerId)
    }

    func picksOutgoing(from teamId: String) -> [PickMovement] {
        pickMovements.filter { $0.fromTeamId == teamId }
    }

    func picksIncoming(to teamId: String) -> [PickMovement] {
        pickMovements.filter { $0.toTeamId == teamId }
    }

    func cash(from teamId: String) -> Int { cashSent[teamId] ?? 0 }

    var teamIds: Set<String> { Set(teams.map(\.teamId)) }
}

struct PlayerMovement: Codable, Identifiable, Hashable {
    let id = UUID()   // local list identity only — intentionally not (de)coded
    let playerId: String
    let fromTeamId: String
    let toTeamId: String
    private enum CodingKeys: String, CodingKey { case playerId, fromTeamId, toTeamId }
}

/// A waived player whose (guaranteed) salary stays on the cap as dead money.
/// Carries yearsRemaining + a stretch flag so the stretch provision can be
/// computed later WITHOUT changing call sites (deadMoneyHit branches on it).
struct WaivedContract: Codable, Identifiable, Hashable {
    let id = UUID()           // local list identity only — intentionally not (de)coded
    let playerId: String
    let teamId: String
    let salary: Int           // current-season salary at waive time (full dead money for now)
    let yearsRemaining: Int   // retained for future stretch math
    var stretch: Bool = false // future: true → spread over (2*yearsRemaining)+1
    private enum CodingKeys: String, CodingKey { case playerId, teamId, salary, yearsRemaining, stretch }
}

struct DismissedPlayer: Codable, Identifiable, Hashable {
    let id = UUID()   // local list identity only — intentionally not (de)coded
    let playerId: String
    let teamId: String
    private enum CodingKeys: String, CodingKey { case playerId, teamId }
}

struct TradeValidation {
    let isValid: Bool
    let reason: String
}

struct PositionFitWarning: Identifiable {
    let id = UUID()
    let playerName: String
    let receivingTeamId: String
    let message: String
}
