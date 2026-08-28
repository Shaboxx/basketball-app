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

    // MARK: - Phase-4.5 family rosters (historical pool)

    /// Guard / Guard / Wing / Wing / Big over the collapsed FAMILY codes
    /// (GUARD/WING/BIG) that historical entities carry in `position` (Sol Option
    /// A primary-family collapse). Each slot accepts exactly its family, so a
    /// BIG-collapsed player fills only the Big slot, etc.
    static let familyFive = RosterConfig(slots: [
        RosterSlot(id: "G1", label: "Guard", allowedPositions: ["GUARD"]),
        RosterSlot(id: "G2", label: "Guard", allowedPositions: ["GUARD"]),
        RosterSlot(id: "W1", label: "Wing", allowedPositions: ["WING"]),
        RosterSlot(id: "W2", label: "Wing", allowedPositions: ["WING"]),
        RosterSlot(id: "B1", label: "Big", allowedPositions: ["BIG"]),
    ])

    /// familyFive + a 6th positionless FLEX slot (Sol: any family) — the 2020s
    /// six-man rotation. Empty `allowedPositions` ⟹ `RosterSlot.accepts` returns
    /// true for any entity.
    static let familySixFlex = RosterConfig(slots: [
        RosterSlot(id: "G1", label: "Guard", allowedPositions: ["GUARD"]),
        RosterSlot(id: "G2", label: "Guard", allowedPositions: ["GUARD"]),
        RosterSlot(id: "W1", label: "Wing", allowedPositions: ["WING"]),
        RosterSlot(id: "W2", label: "Wing", allowedPositions: ["WING"]),
        RosterSlot(id: "B1", label: "Big", allowedPositions: ["BIG"]),
        RosterSlot(id: "FLEX", label: "Flex", allowedPositions: []),
    ])
}

/// How a finished game is judged (spec §§24–25 subset). `none` = side-by-side
/// result with no declared winner — the honest default for subjective drafts.
/// `teamRating` sums each roster's `rating`. `slotMetric` (Phase 8
/// COMPOSITE_BUILDER) sums, per assignment, the value of the CompareMetric mapped
/// to that assignment's `slotId` — a "Create-A-Player" style per-slot scoring
/// policy. It is a scoring extension of ROSTER_CONSTRUCTION, NOT a new engine
/// (Sol §112); the interaction stays "fill constrained slots from a pool".
///
/// Hand-written Codable so the ADDITIVE `slotMetric` case is forward/backward
/// compatible: the two legacy cases still encode as the bare strings
/// `"teamRating"` / `"none"` (byte-identical to the old `RawRepresentable`
/// form), so every previously-encoded definition still decodes. `slotMetric`
/// encodes as an object `{"slotMetric":{slotId:metric,…}}`.
nonisolated enum ScoringMethod: Codable, Equatable, Hashable {
    case teamRating
    case none
    case slotMetric([String: CompareMetric])

    private enum CodingKeys: String, CodingKey { case slotMetric }

    init(from decoder: Decoder) throws {
        // Legacy form: a bare string ("teamRating" | "none").
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch raw {
            case "teamRating": self = .teamRating; return
            case "none":       self = .none; return
            default: break     // fall through to the keyed form
            }
        }
        // New form: {"slotMetric": {slotId: metric, …}}.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let map = try c.decode([String: CompareMetric].self, forKey: .slotMetric)
        self = .slotMetric(map)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .teamRating:
            var c = encoder.singleValueContainer()
            try c.encode("teamRating")
        case .none:
            var c = encoder.singleValueContainer()
            try c.encode("none")
        case .slotMetric(let map):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(map, forKey: .slotMetric)
        }
    }
}

/// Where a game's entity pool comes from (Phase-4.5). ADDITIVE + optional on
/// `GameDefinition` — the engine NEVER reads it; only the View layer branches on
/// it to source the pool from the live players (`.current`) or the bundled
/// historical dataset (`.historical`). `.current` is the default, so every
/// existing encoded definition (which lacks the key) reads as `.current`.
///
/// Codable by hand (an associated-value enum) so the encoded form stays small
/// and forward-compatible: `{"kind":"current"}` or
/// `{"kind":"historical","filter":{…}}`.
nonisolated enum GamePoolSource: Codable, Equatable {
    case current
    case historical(HistoricalFilter)

    private enum CodingKeys: String, CodingKey { case kind, filter }
    private enum Kind: String, Codable { case current, historical }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .current:
            self = .current
        case .historical:
            let filter = try c.decode(HistoricalFilter.self, forKey: .filter)
            self = .historical(filter)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .current:
            try c.encode(Kind.current, forKey: .kind)
        case .historical(let filter):
            try c.encode(Kind.historical, forKey: .kind)
            try c.encode(filter, forKey: .filter)
        }
    }
}

/// Spec §3 GameDefinition. Phase-1 core + Phase-2 optional modifiers. The
/// entity-constraint list IS the player pool filter (a separate PlayerPool
/// object becomes meaningful when historical pools land — roadmap Phase 4).
/// The three modifiers are optional and default to nil, so every Phase-1 game
/// (and its encoded form) is unchanged: synthesized Codable decodes absent keys
/// as nil.
nonisolated struct GameDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let engineType: GameEngineType
    let entityConstraints: [GameConstraint]
    let rosterConstraints: [RosterConstraint]
    let roster: RosterConfig
    let selection: SelectionConfig
    let scoring: ScoringMethod
    let economy: EconomyConfig?
    let reveal: RevealConfig?
    let specialActions: SpecialActionsConfig?
    /// Phase-4.5 additive pool source. Defaults to `.current`; NO engine reads
    /// it — only the roster DESTINATION view branches on it (HistoricalRosterDraftView
    /// vs RosterDraftView). Decoded with `decodeIfPresent` so every Phase-1
    /// encoded definition (which lacks the key) still decodes as `.current`.
    let poolSource: GamePoolSource

    init(id: String, title: String, engineType: GameEngineType,
         entityConstraints: [GameConstraint], rosterConstraints: [RosterConstraint],
         roster: RosterConfig, selection: SelectionConfig, scoring: ScoringMethod,
         economy: EconomyConfig? = nil, reveal: RevealConfig? = nil,
         specialActions: SpecialActionsConfig? = nil,
         poolSource: GamePoolSource = .current) {
        self.id = id
        self.title = title
        self.engineType = engineType
        self.entityConstraints = entityConstraints
        self.rosterConstraints = rosterConstraints
        self.roster = roster
        self.selection = selection
        self.scoring = scoring
        self.economy = economy
        self.reveal = reveal
        self.specialActions = specialActions
        self.poolSource = poolSource
    }

    // Hand-written Codable so `poolSource` is a FORGIVING addition: an existing
    // encoded definition (no `poolSource` key) decodes to `.current`, and all
    // other keys keep their synthesized behavior. Every stored property is
    // required except the modifiers (optional) + `poolSource` (defaulted).
    enum CodingKeys: String, CodingKey {
        case id, title, engineType, entityConstraints, rosterConstraints
        case roster, selection, scoring, economy, reveal, specialActions, poolSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        engineType = try c.decode(GameEngineType.self, forKey: .engineType)
        entityConstraints = try c.decode([GameConstraint].self, forKey: .entityConstraints)
        rosterConstraints = try c.decode([RosterConstraint].self, forKey: .rosterConstraints)
        roster = try c.decode(RosterConfig.self, forKey: .roster)
        selection = try c.decode(SelectionConfig.self, forKey: .selection)
        scoring = try c.decode(ScoringMethod.self, forKey: .scoring)
        economy = try c.decodeIfPresent(EconomyConfig.self, forKey: .economy)
        reveal = try c.decodeIfPresent(RevealConfig.self, forKey: .reveal)
        specialActions = try c.decodeIfPresent(SpecialActionsConfig.self, forKey: .specialActions)
        poolSource = try c.decodeIfPresent(GamePoolSource.self, forKey: .poolSource) ?? .current
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(engineType, forKey: .engineType)
        try c.encode(entityConstraints, forKey: .entityConstraints)
        try c.encode(rosterConstraints, forKey: .rosterConstraints)
        try c.encode(roster, forKey: .roster)
        try c.encode(selection, forKey: .selection)
        try c.encode(scoring, forKey: .scoring)
        try c.encodeIfPresent(economy, forKey: .economy)
        try c.encodeIfPresent(reveal, forKey: .reveal)
        try c.encodeIfPresent(specialActions, forKey: .specialActions)
        try c.encode(poolSource, forKey: .poolSource)
    }
}
