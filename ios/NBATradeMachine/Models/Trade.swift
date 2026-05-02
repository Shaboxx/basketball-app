import Foundation

struct Trade {
    var teams: [Team] = []
    var movements: [PlayerMovement] = []

    mutating func reset() {
        teams.removeAll()
        movements.removeAll()
    }

    func incomingPlayerIds(to teamId: String) -> [String] {
        movements.filter { $0.toTeamId == teamId }.map(\.playerId)
    }

    func outgoingPlayerIds(from teamId: String) -> [String] {
        movements.filter { $0.fromTeamId == teamId }.map(\.playerId)
    }

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
