import Foundation

/// A per-player `matchups/{slug}` doc. NOTE: the doc uses **snake_case** keys (produced
/// by the Python aggregate), so every CodingKey maps the snake_case string explicitly.
/// Nullable rate fields are Double? (the Python guard emits null at zero possessions).
nonisolated struct Matchup: Codable, Equatable {
    let defense: Defense
    let offense: Offense
    let byPosition: [String: PositionSplit]
    let topMatchups: TopMatchups
    /// Generic passthrough of the 10 tracking families ({family: {stat: value}}); decoded
    /// but unused in SP1 (SP2 play-style fingerprint consumes it).
    let tracking: [String: [String: Double]]

    enum CodingKeys: String, CodingKey {
        case defense, offense, tracking
        case byPosition = "by_position"
        case topMatchups = "top_matchups"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        defense = try c.decodeIfPresent(Defense.self, forKey: .defense) ?? .zero
        offense = try c.decodeIfPresent(Offense.self, forKey: .offense) ?? .zero
        byPosition = try c.decodeIfPresent([String: PositionSplit].self, forKey: .byPosition) ?? [:]
        topMatchups = try c.decodeIfPresent(TopMatchups.self, forKey: .topMatchups) ?? .zero
        tracking = try c.decodeIfPresent([String: [String: Double]].self, forKey: .tracking) ?? [:]
    }
    init(defense: Defense, offense: Offense, byPosition: [String: PositionSplit],
         topMatchups: TopMatchups, tracking: [String: [String: Double]] = [:]) {
        self.defense = defense; self.offense = offense; self.byPosition = byPosition
        self.topMatchups = topMatchups; self.tracking = tracking
    }

    struct Defense: Codable, Equatable {
        let totalPossGuarded, oppPts: Double
        let oppPtsPerPoss, oppEfgAllowed: Double?
        enum CodingKeys: String, CodingKey {
            case totalPossGuarded = "total_poss_guarded", oppPts = "opp_pts"
            case oppPtsPerPoss = "opp_pts_per_poss", oppEfgAllowed = "opp_efg_allowed"
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            totalPossGuarded = try c.decodeIfPresent(Double.self, forKey: .totalPossGuarded) ?? 0
            oppPts = try c.decodeIfPresent(Double.self, forKey: .oppPts) ?? 0
            oppPtsPerPoss = try c.decodeIfPresent(Double.self, forKey: .oppPtsPerPoss)
            oppEfgAllowed = try c.decodeIfPresent(Double.self, forKey: .oppEfgAllowed)
        }
        init(totalPossGuarded: Double, oppPts: Double, oppPtsPerPoss: Double?, oppEfgAllowed: Double?) {
            self.totalPossGuarded = totalPossGuarded; self.oppPts = oppPts
            self.oppPtsPerPoss = oppPtsPerPoss; self.oppEfgAllowed = oppEfgAllowed
        }
        static let zero = Defense(totalPossGuarded: 0, oppPts: 0, oppPtsPerPoss: nil, oppEfgAllowed: nil)
    }

    struct Offense: Codable, Equatable {
        let totalPossAsOffender, pts: Double
        let ptsPerPoss, efg: Double?
        enum CodingKeys: String, CodingKey {
            case totalPossAsOffender = "total_poss_as_offender", pts
            case ptsPerPoss = "pts_per_poss", efg
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            totalPossAsOffender = try c.decodeIfPresent(Double.self, forKey: .totalPossAsOffender) ?? 0
            pts = try c.decodeIfPresent(Double.self, forKey: .pts) ?? 0
            ptsPerPoss = try c.decodeIfPresent(Double.self, forKey: .ptsPerPoss)
            efg = try c.decodeIfPresent(Double.self, forKey: .efg)
        }
        init(totalPossAsOffender: Double, pts: Double, ptsPerPoss: Double?, efg: Double?) {
            self.totalPossAsOffender = totalPossAsOffender; self.pts = pts; self.ptsPerPoss = ptsPerPoss; self.efg = efg
        }
        static let zero = Offense(totalPossAsOffender: 0, pts: 0, ptsPerPoss: nil, efg: nil)
    }

    struct PositionSplit: Codable, Equatable {
        let partialPoss, pts: Double
        let ptsPerPoss: Double?
        enum CodingKeys: String, CodingKey {
            case partialPoss = "partial_poss", pts, ptsPerPoss = "pts_per_poss"
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            partialPoss = try c.decodeIfPresent(Double.self, forKey: .partialPoss) ?? 0
            pts = try c.decodeIfPresent(Double.self, forKey: .pts) ?? 0
            ptsPerPoss = try c.decodeIfPresent(Double.self, forKey: .ptsPerPoss)
        }
        init(partialPoss: Double, pts: Double, ptsPerPoss: Double?) {
            self.partialPoss = partialPoss; self.pts = pts; self.ptsPerPoss = ptsPerPoss
        }
    }

    struct Opponent: Codable, Equatable, Identifiable {
        let offPlayerId: Int
        let offName: String
        let partialPoss, pts: Double
        let ptsPerPoss: Double?
        var id: Int { offPlayerId }
        enum CodingKeys: String, CodingKey {
            case offPlayerId = "off_player_id", offName = "off_name"
            case partialPoss = "partial_poss", pts, ptsPerPoss = "pts_per_poss"
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            offPlayerId = try c.decodeIfPresent(Int.self, forKey: .offPlayerId) ?? 0
            offName = try c.decodeIfPresent(String.self, forKey: .offName) ?? ""
            partialPoss = try c.decodeIfPresent(Double.self, forKey: .partialPoss) ?? 0
            pts = try c.decodeIfPresent(Double.self, forKey: .pts) ?? 0
            ptsPerPoss = try c.decodeIfPresent(Double.self, forKey: .ptsPerPoss)
        }
        init(offPlayerId: Int, offName: String, partialPoss: Double, pts: Double, ptsPerPoss: Double?) {
            self.offPlayerId = offPlayerId; self.offName = offName
            self.partialPoss = partialPoss; self.pts = pts; self.ptsPerPoss = ptsPerPoss
        }
    }

    struct TopMatchups: Codable, Equatable {
        let mostFrequent, toughest: [Opponent]
        enum CodingKeys: String, CodingKey { case mostFrequent = "most_frequent", toughest }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            mostFrequent = try c.decodeIfPresent([Opponent].self, forKey: .mostFrequent) ?? []
            toughest = try c.decodeIfPresent([Opponent].self, forKey: .toughest) ?? []
        }
        init(mostFrequent: [Opponent], toughest: [Opponent]) {
            self.mostFrequent = mostFrequent; self.toughest = toughest
        }
        static let zero = TopMatchups(mostFrequent: [], toughest: [])
    }
}
