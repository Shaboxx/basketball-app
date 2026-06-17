import Foundation

// MARK: - Forward-compatible enums (unknown raw values never throw)

nonisolated enum TxnKind: String, Codable {
    case fa, trade, unknown
    init(from d: Decoder) throws {
        self = TxnKind(rawValue: try d.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

nonisolated enum TxnSource: String, Codable {
    case deterministic, ai, unknown
    init(from d: Decoder) throws {
        self = TxnSource(rawValue: try d.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

// MARK: - Transaction variants

nonisolated struct FATxn: Codable, Equatable {
    let source: TxnSource
    let type: String
    let playerId: String?
    let name: String?
    let team: String?
    let fromTeam: String?
    let firstYear: Int?
    let years: Int?

    enum CodingKeys: String, CodingKey {
        case source, type, team, years, name
        case playerId = "player_id"
        case fromTeam = "from_team"
        case firstYear = "first_year"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(TxnSource.self, forKey: .source) ?? .unknown
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        playerId = try c.decodeIfPresent(String.self, forKey: .playerId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        fromTeam = try c.decodeIfPresent(String.self, forKey: .fromTeam)
        firstYear = try c.decodeIfPresent(Int.self, forKey: .firstYear)
        years = try c.decodeIfPresent(Int.self, forKey: .years)
    }
}

nonisolated struct TradePlayer: Codable, Equatable {
    let playerId: String
    let name: String?
    let from: String?
    let to: String?
    let salary: Int?
    enum CodingKeys: String, CodingKey {
        case name, from, to, salary
        case playerId = "player_id"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decodeIfPresent(String.self, forKey: .playerId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        to = try c.decodeIfPresent(String.self, forKey: .to)
        salary = try c.decodeIfPresent(Int.self, forKey: .salary)
    }
}

nonisolated struct TradeTxn: Codable, Equatable {
    let source: TxnSource
    let round: Int?
    let teams: [String]
    let players: [TradePlayer]
    let totalGain: Double?
    enum CodingKeys: String, CodingKey {
        case source, round, teams, players
        case totalGain = "total_gain"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(TxnSource.self, forKey: .source) ?? .unknown
        round = try c.decodeIfPresent(Int.self, forKey: .round)
        teams = try c.decodeIfPresent([String].self, forKey: .teams) ?? []
        players = try c.decodeIfPresent([TradePlayer].self, forKey: .players) ?? []
        totalGain = try c.decodeIfPresent(Double.self, forKey: .totalGain)
    }
}

/// A `kind`-discriminated transaction. FA and trade have different field shapes;
/// an unknown/absent `kind` decodes to `.unknown` (never throws).
nonisolated enum OffseasonTransaction: Decodable, Identifiable, Equatable {
    case fa(FATxn)
    case trade(TradeTxn)
    case unknown

    private enum KindKey: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: KindKey.self)
        switch try k.decodeIfPresent(TxnKind.self, forKey: .kind) ?? .unknown {
        case .fa: self = .fa(try FATxn(from: decoder))
        case .trade: self = .trade(try TradeTxn(from: decoder))
        case .unknown: self = .unknown
        }
    }

    var id: String {
        switch self {
        case .fa(let f): return "fa:\(f.playerId ?? "?")->\(f.team ?? "?"):\(f.type)"
        case .trade(let t): return "trade:\(t.teams.joined(separator: "-")):" + t.players.map { $0.playerId }.joined(separator: ",")
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Supporting models

nonisolated struct CapSheet: Codable, Equatable {
    let tricode: String?
    let teamSalary: Int?
    let capRoom: Int?
    let capTier: String?
    let apronStatus: String?
    let operatingMode: String?
    let belowFloor: Bool?
    let hardCap: Bool?
    enum CodingKeys: String, CodingKey {
        case tricode
        case teamSalary = "team_salary"
        case capRoom = "cap_room"
        case capTier = "cap_tier"
        case apronStatus = "apron_status"
        case operatingMode = "operating_mode"
        case belowFloor = "below_floor"
        case hardCap = "hard_cap"
    }
}

nonisolated struct UnsignedFA: Codable, Equatable, Identifiable {
    var id: String { playerId }
    let playerId: String
    let name: String
    let team: String?
    let value: Int?
    let faType: String?
    let reason: String?
    enum CodingKeys: String, CodingKey {
        case name, team, value, reason
        case playerId = "player_id"
        case faType = "fa_type"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decodeIfPresent(String.self, forKey: .playerId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        team = try c.decodeIfPresent(String.self, forKey: .team)
        value = try c.decodeIfPresent(Int.self, forKey: .value)
        faType = try c.decodeIfPresent(String.self, forKey: .faType)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

nonisolated struct UntradedBlock: Codable, Equatable, Identifiable {
    var id: String { "\(team):\(playerId)" }
    let team: String
    let playerId: String
    enum CodingKeys: String, CodingKey { case team; case playerId = "player_id" }
}

nonisolated struct AISummary: Codable, Equatable {
    let accepted: Int
    let rejected: Int
    init(accepted: Int, rejected: Int) { self.accepted = accepted; self.rejected = rejected }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try c.decodeIfPresent(Int.self, forKey: .accepted) ?? 0
        rejected = try c.decodeIfPresent(Int.self, forKey: .rejected) ?? 0
    }
    enum CodingKeys: String, CodingKey { case accepted, rejected }
}

nonisolated struct TeamIndexEntry: Codable, Equatable, Identifiable {
    var id: String { tricode }
    let tricode: String
    let nMoves: Int
    let capTier: String?
    let teamSalary: Int?
    enum CodingKeys: String, CodingKey {
        case tricode
        case nMoves = "n_moves"
        case capTier = "cap_tier"
        case teamSalary = "team_salary"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tricode = try c.decodeIfPresent(String.self, forKey: .tricode) ?? ""
        nMoves = try c.decodeIfPresent(Int.self, forKey: .nMoves) ?? 0
        capTier = try c.decodeIfPresent(String.self, forKey: .capTier)
        teamSalary = try c.decodeIfPresent(Int.self, forKey: .teamSalary)
    }
}

// MARK: - Top-level docs

nonisolated struct OffseasonSummary: Decodable, Equatable {
    let season: String
    let generatedAt: String?
    let model: String?
    let aiRan: Bool
    let nAiMoves: Int
    let narrative: String
    let transactions: [OffseasonTransaction]
    let unsignedFAs: [UnsignedFA]
    let untradedBlocks: [UntradedBlock]
    let aiSummary: AISummary
    let warnings: [String]
    let teamIndex: [TeamIndexEntry]
    let transactionsTruncated: Bool

    enum CodingKeys: String, CodingKey {
        case season, generatedAt, model, narrative, transactions, warnings   // generatedAt already camelCase in Firestore
        case aiRan = "ai_ran"
        case nAiMoves = "n_ai_moves"
        case unsignedFAs = "unsigned_fas"
        case untradedBlocks = "untraded_blocks"
        case aiSummary = "ai_summary"
        case teamIndex = "team_index"
        case transactionsTruncated = "transactions_truncated"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        season = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        aiRan = try c.decodeIfPresent(Bool.self, forKey: .aiRan) ?? false
        nAiMoves = try c.decodeIfPresent(Int.self, forKey: .nAiMoves) ?? 0
        narrative = try c.decodeIfPresent(String.self, forKey: .narrative) ?? ""
        transactions = try c.decodeIfPresent([OffseasonTransaction].self, forKey: .transactions) ?? []
        unsignedFAs = try c.decodeIfPresent([UnsignedFA].self, forKey: .unsignedFAs) ?? []
        untradedBlocks = try c.decodeIfPresent([UntradedBlock].self, forKey: .untradedBlocks) ?? []
        aiSummary = try c.decodeIfPresent(AISummary.self, forKey: .aiSummary) ?? AISummary(accepted: 0, rejected: 0)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        teamIndex = try c.decodeIfPresent([TeamIndexEntry].self, forKey: .teamIndex) ?? []
        transactionsTruncated = try c.decodeIfPresent(Bool.self, forKey: .transactionsTruncated) ?? false
    }

    /// Convenience init for tests/previews.
    init(season: String, generatedAt: String? = nil, model: String? = nil, aiRan: Bool = false,
         nAiMoves: Int = 0, narrative: String = "", transactions: [OffseasonTransaction] = [],
         unsignedFAs: [UnsignedFA] = [], untradedBlocks: [UntradedBlock] = [],
         aiSummary: AISummary = AISummary(accepted: 0, rejected: 0), warnings: [String] = [],
         teamIndex: [TeamIndexEntry] = [], transactionsTruncated: Bool = false) {
        self.season = season; self.generatedAt = generatedAt; self.model = model; self.aiRan = aiRan
        self.nAiMoves = nAiMoves; self.narrative = narrative; self.transactions = transactions
        self.unsignedFAs = unsignedFAs; self.untradedBlocks = untradedBlocks; self.aiSummary = aiSummary
        self.warnings = warnings; self.teamIndex = teamIndex; self.transactionsTruncated = transactionsTruncated
    }
}

nonisolated struct TeamOffseason: Decodable, Equatable {
    let tricode: String
    let season: String
    let generatedAt: String?
    let capBefore: CapSheet?
    let capAfter: CapSheet?
    let acquired: [String]
    let dealt: [String]
    let transactions: [OffseasonTransaction]

    enum CodingKeys: String, CodingKey {
        case tricode, season, generatedAt, acquired, dealt, transactions
        case capBefore = "cap_before"
        case capAfter = "cap_after"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tricode = try c.decodeIfPresent(String.self, forKey: .tricode) ?? ""
        season = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        capBefore = try c.decodeIfPresent(CapSheet.self, forKey: .capBefore)
        capAfter = try c.decodeIfPresent(CapSheet.self, forKey: .capAfter)
        acquired = try c.decodeIfPresent([String].self, forKey: .acquired) ?? []
        dealt = try c.decodeIfPresent([String].self, forKey: .dealt) ?? []
        transactions = try c.decodeIfPresent([OffseasonTransaction].self, forKey: .transactions) ?? []
    }

    /// Convenience init for tests/previews.
    init(tricode: String, season: String, generatedAt: String? = nil, capBefore: CapSheet? = nil,
         capAfter: CapSheet? = nil, acquired: [String] = [], dealt: [String] = [],
         transactions: [OffseasonTransaction] = []) {
        self.tricode = tricode; self.season = season; self.generatedAt = generatedAt
        self.capBefore = capBefore; self.capAfter = capAfter; self.acquired = acquired
        self.dealt = dealt; self.transactions = transactions
    }
}
