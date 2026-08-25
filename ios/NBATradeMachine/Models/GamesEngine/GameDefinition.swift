import Foundation

/// Which runtime handles a definition (spec §3). Phase 1 ships one engine;
/// later phases append cases (classification, grid, …).
nonisolated enum GameEngineType: String, Codable, Equatable {
    case rosterConstruction
}

/// How picks happen (spec §8 subset — auction/pack/nomination are later phases).
nonisolated enum SelectionMethod: String, Codable, Equatable {
    case freePick, snake, randomOffer
}

nonisolated struct SelectionConfig: Codable, Equatable {
    var method: SelectionMethod
    var sharedPool: Bool        // true → a picked entity leaves everyone's pool
    var offeringsPerTurn: Int?  // randomOffer only

    static let freePick = SelectionConfig(method: .freePick, sharedPool: false,
                                          offeringsPerTurn: nil)
    static let snake = SelectionConfig(method: .snake, sharedPool: true,
                                       offeringsPerTurn: nil)
    static func randomOffer(_ n: Int) -> SelectionConfig {
        SelectionConfig(method: .randomOffer, sharedPool: true, offeringsPerTurn: n)
    }
}

/// One roster slot (spec §7). Empty `allowedPositions` = positionless.
nonisolated struct RosterSlot: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let allowedPositions: [String]

    func accepts(_ entity: GameEntityRecord) -> Bool {
        allowedPositions.isEmpty || allowedPositions.contains(entity.position)
    }
}

nonisolated struct RosterConfig: Codable, Equatable {
    let slots: [RosterSlot]

    /// Strict PG/SG/SF/PF/C.
    static let startingFive = RosterConfig(slots:
        ["PG", "SG", "SF", "PF", "C"].map {
            RosterSlot(id: $0, label: $0, allowedPositions: [$0])
        })

    /// Guard/Guard/Wing/Wing/Big — playable with single-position player data.
    static let flexFive = RosterConfig(slots: [
        RosterSlot(id: "G1", label: "Guard", allowedPositions: ["PG", "SG"]),
        RosterSlot(id: "G2", label: "Guard", allowedPositions: ["PG", "SG"]),
        RosterSlot(id: "W1", label: "Wing", allowedPositions: ["SG", "SF", "PF"]),
        RosterSlot(id: "W2", label: "Wing", allowedPositions: ["SF", "PF"]),
        RosterSlot(id: "B1", label: "Big", allowedPositions: ["PF", "C"]),
    ])

    static func positionless(_ count: Int) -> RosterConfig {
        RosterConfig(slots: (1...count).map {
            RosterSlot(id: "P\($0)", label: "Player \($0)", allowedPositions: [])
        })
    }
}

/// How a finished game is judged (spec §§24–25 subset). `none` = side-by-side
/// result with no declared winner — the honest default for subjective drafts.
nonisolated enum ScoringMethod: String, Codable, Equatable {
    case teamRating
    case none
}

/// Spec §3 GameDefinition, Phase-1 subset. The entity-constraint list IS the
/// player pool filter (a separate PlayerPool object becomes meaningful when
/// historical pools land — roadmap Phase 4).
nonisolated struct GameDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let engineType: GameEngineType
    let entityConstraints: [GameConstraint]
    let rosterConstraints: [RosterConstraint]
    let roster: RosterConfig
    let selection: SelectionConfig
    let scoring: ScoringMethod
}
