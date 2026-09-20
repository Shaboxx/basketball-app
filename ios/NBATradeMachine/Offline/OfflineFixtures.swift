import Foundation

/// Deterministic, fictional data. Ratings and salaries are illustrative inputs,
/// not model predictions or factual player valuations.
enum OfflineFixtures {
    static let players: [Player] = (0..<20).map { index in
        let positions = ["PG", "SG", "SF", "PF", "C"]
        let teams = ["lake", "prairie", "coast", "ridge"]
        let payload: [String: Any] = [
            "slug": "sample-player-\(index + 1)",
            "name": "Sample Player \(index + 1)",
            "teamId": teams[index / 5], "position": positions[index % 5],
            "heightInches": 73 + (index % 5) * 2,
            "salaryY1": 4_000_000 + index * 750_000,
            "salaryY2": 4_200_000 + index * 750_000,
            "thetaBoard": ["total": Double(index % 11) / 2 - 1,
                           "off": Double(index % 7) / 2,
                           "def": Double(index % 11) / 2 - 1 - Double(index % 7) / 2]
        ]
        return try! JSONDecoder().decode(Player.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static let teams: [Team] = [
        Team(teamId: "lake", fullName: "Lake City Waves", city: "Lake City", name: "Waves", conference: "East", division: "Demo"),
        Team(teamId: "prairie", fullName: "Prairie Town Stars", city: "Prairie Town", name: "Stars", conference: "East", division: "Demo"),
        Team(teamId: "coast", fullName: "Coast City Comets", city: "Coast City", name: "Comets", conference: "West", division: "Demo"),
        Team(teamId: "ridge", fullName: "Ridge Town Owls", city: "Ridge Town", name: "Owls", conference: "West", division: "Demo")
    ]

    static var pool: [GameEntityRecord] { GamePoolBuilder.pool(from: players) }

    static func context(teamId: String, outgoing: [Player], incoming: [Player]) -> TeamContext {
        let roster = players.filter { $0.teamId == teamId }
        let outSum = outgoing.reduce(0) { $0 + $1.currentSalary }
        let inSum = incoming.reduce(0) { $0 + $1.currentSalary }
        let preSalary = roster.reduce(0) { $0 + $1.currentSalary }
        func contract(_ p: Player) -> ContractLite {
            ContractLite(playerId: p.slug, name: p.name, salaryY1: p.currentSalary,
                         standardMax: p.standardMax, nextContractMax: p.nextContractMax)
        }
        return TeamContext(teamId: teamId, teamName: teams.first { $0.teamId == teamId }!.fullName,
            preTradeSalary: preSalary, postTradeSalary: preSalary - outSum + inSum,
            postTradeTier: .underCap, incoming: incoming.map(contract), outgoing: outgoing.map(contract),
            cashSent: 0, postTradeRosterCount: roster.count - outgoing.count + incoming.count,
            isOffseason: true, ownedFirstRoundYears: Set(2027...2033),
            preTradeOwnedFirstRoundYears: Set(2027...2033), draftYearHorizon: 2027...2033,
            hardCapLimit: nil, acquiringViaSignAndTrade: false, signAndTradePriorTeamIds: [],
            tradeTeamIds: Set(teams.map(\.teamId)), signedExceptions: [], signAndTradeAcquiredYears: [],
            conveyedFirstRoundYears: [], conveyedPickYears: [], currentDraftYear: 2027, cashReceived: 0,
            twoWayCount: nil, scenarioDate: nil, standingTPEs: [])
    }
}
