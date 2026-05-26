import Foundation

struct Trade {
    static let cashLimit: Int = 8_120_000

    var teams: [Team] = []
    var movements: [PlayerMovement] = []
    var pickMovements: [PickMovement] = []
    var cashSent: [String: Int] = [:]

    mutating func reset() {
        teams.removeAll()
        movements.removeAll()
        pickMovements.removeAll()
        cashSent.removeAll()
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

struct PlayerMovement: Identifiable, Hashable {
    let id = UUID()
    let playerId: String
    let fromTeamId: String
    let toTeamId: String
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
