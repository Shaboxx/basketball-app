import Foundation

enum TradeAnalyzer {

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

    /// STRUCTURAL guard only: each team must send AND receive a player. Salary-
    /// MATCHING legality is tier-aware and lives in `TradeCompliance.salaryMatchIssues`
    /// — a flat 125%+$250k cap here wrongly blocked legal under-cap room-absorption
    /// and over-cap expanded-TPE (up to 200%) trades the compliance engine allows.
    static func validate(flows: [TeamFlow]) -> TradeValidation {
        guard !flows.isEmpty else {
            return TradeValidation(isValid: false, reason: "Add teams and players to the trade.")
        }
        for flow in flows {
            // Each team must be INVOLVED (move salary in or out). One-way salary flows
            // are legal — an under-cap / TPE team can absorb a player for a pick or cash
            // (no outgoing salary), and a team can dump salary for a pick. The receiver's
            // room and all salary matching are enforced by TradeCompliance.
            if flow.outgoing == 0 && flow.incoming == 0 {
                return TradeValidation(isValid: false, reason: "\(flow.teamName) isn't sending or receiving salary in this trade.")
            }
        }
        return TradeValidation(isValid: true, reason: "Every team is involved in the trade.")
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
