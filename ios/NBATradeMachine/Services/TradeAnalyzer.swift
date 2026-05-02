import Foundation

enum TradeAnalyzer {

    private static let salaryMatchMultiplier: Double = 1.25
    private static let salaryMatchBuffer: Int = 250_000

    private static let avgHeightByPosition: [String: Double] = [
        "PG": 75.0, "SG": 77.0, "SF": 79.0, "PF": 81.0, "C": 83.0
    ]
    private static let positionStdDev: Double = 2.5

    struct TeamFlow {
        let teamId: String
        let teamName: String
        let outgoing: Int
        let incoming: Int
    }

    static func validate(flows: [TeamFlow]) -> TradeValidation {
        guard !flows.isEmpty else {
            return TradeValidation(isValid: false, reason: "Add teams and players to the trade.")
        }
        for flow in flows {
            if flow.outgoing == 0 || flow.incoming == 0 {
                return TradeValidation(isValid: false, reason: "\(flow.teamName) must send and receive at least one player.")
            }
        }
        for flow in flows {
            let cap = Int(Double(flow.outgoing) * salaryMatchMultiplier) + salaryMatchBuffer
            if flow.incoming > cap {
                return TradeValidation(isValid: false, reason: "\(flow.teamName) is taking back too much salary (over 125% + $250k).")
            }
        }
        return TradeValidation(isValid: true, reason: "Salaries match for all teams (within 125% + $250k).")
    }

    static func fitWarnings(incoming: [Player], receivingRoster: [Player], teamId: String) -> [PositionFitWarning] {
        var warnings: [PositionFitWarning] = []
        let topThree = receivingRoster.sorted { $0.currentSalary > $1.currentSalary }.prefix(3)
        let topRoles = Set(topThree.compactMap { $0.primaryRole })
        for player in incoming {
            if let role = player.primaryRole, topRoles.contains(role) {
                warnings.append(PositionFitWarning(
                    playerName: player.name,
                    receivingTeamId: teamId,
                    message: "Role overlap: \(role) already on roster's top-3."
                ))
            }
            if let h = player.heightInches, let avg = avgHeightByPosition[player.position] {
                let z = (Double(h) - avg) / positionStdDev
                if z < -1.0 {
                    warnings.append(PositionFitWarning(
                        playerName: player.name,
                        receivingTeamId: teamId,
                        message: "May be undersized for \(player.position) (z=\(String(format: "%.1f", z)))."
                    ))
                }
            }
        }
        return warnings
    }
}
