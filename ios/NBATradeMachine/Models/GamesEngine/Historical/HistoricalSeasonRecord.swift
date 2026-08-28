import Foundation

/// Pure decode targets for the bundled `game-players-historical.json`
/// (14569 player-season records, 30 seasons 1996-97…2025-26). These mirror the
/// JSON shape verbatim and carry NO engine logic — `HistoricalPoolBuilder` maps
/// them into the frozen `GameEntityRecord` shape the proven engine consumes.
///
/// All types are `nonisolated` (the app target is default-MainActor; pure value
/// types must opt out of that isolation to stay usable off the main actor, which
/// is where the 12MB decode runs — see `HistoricalPoolStore`).

/// Top-level file: `{ "_meta": {...}, "players": [ … ] }`.
/// Explicitly `Sendable` (all members are Sendable value types) so it can be
/// returned from the store's `Task.detached` decode back to the main actor
/// without a data-race diagnostic under Swift 6.
nonisolated struct HistoricalDataset: Codable, Equatable, Sendable {
    let meta: HistoricalMeta
    let players: [HistoricalSeasonRecord]

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case players
    }
}

/// The `_meta` block. `schemaVersion` is honored by the consumer; the rest is
/// informational (surfaced in tests / future UI). Fields are optional so a
/// future meta shape that drops one still decodes.
nonisolated struct HistoricalMeta: Codable, Equatable, Sendable {
    let schemaVersion: Int?
    let playerSeasonCount: Int?
    let seasons: [String]?
    let generatedAt: String?
    let source: String?
    let ratingDefinition: String?
    let eligibility: HistoricalEligibilityMeta?
}

nonisolated struct HistoricalEligibilityMeta: Codable, Equatable, Sendable {
    let minGp: Int?
    let minMpg: Double?
}

/// One player-season row. `id` is the season-unique key `nba:<playerId>:<season>`
/// so different seasons of the same player are naturally distinct entities
/// (uniqueBy across seasons of one player collides on nothing by default).
nonisolated struct HistoricalSeasonRecord: Codable, Equatable, Sendable {
    let id: String                    // "nba:893:1996-97" — season-unique entity key
    let entityType: String            // "PLAYER_SEASON"
    let nbaPlayerId: Int
    let appSlug: String?              // may be null in the data
    let name: String
    let seasonStartYear: Int
    let seasonLabel: String           // "1996-97"
    let decadeStartYear: Int          // 1990 / 2000 / 2010 / 2020
    let team: String                  // tricode, e.g. "CHI"
    let age: Double?
    let gp: Int?
    let minutes: Double?
    let eligible: Bool
    let positionFamilies: [String]    // non-empty subset of ["GUARD","WING","BIG"]
    let rating: Double
    let offRating: Double?
    let defRating: Double?
    let stats: HistoricalStats?
    let career: HistoricalCareer?
}

/// Per-season box/impact stats. Optional as a block AND per-field so a partial
/// stats object still decodes; a missing field surfaces as `nil` → the
/// corresponding `GameField` is absent → the evaluator's SQL-style missing-field
/// semantics apply unchanged.
nonisolated struct HistoricalStats: Codable, Equatable, Sendable {
    let pts: Double?
    let reb: Double?
    let ast: Double?
    let stl: Double?
    let blk: Double?
    let tov: Double?
    let fgPct: Double?
    let threePct: Double?
    let ftPct: Double?
    let tsPct: Double?
    let usgPct: Double?
    let pie: Double?
    let netRating: Double?
}

/// Career accolades. The whole block may be absent (older seasons / role
/// players) and every field is optional; a missing count means "not known /
/// zero" and surfaces as an absent `GameField` (never satisfies a `>= 1` award
/// gate, by design).
nonisolated struct HistoricalCareer: Codable, Equatable, Sendable {
    let rings: Int?
    let mvp: Int?
    let finalsMvp: Int?
    let allNba: Int?
    let allStar: Int?
    let allDefense: Int?
    let draftYear: Int?
    let draftRound: Int?
    let draftPick: Int?
}
