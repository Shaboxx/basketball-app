import Foundation

/// The lifecycle of a league trade proposal. Mirrors ESPN/Yahoo: a manager
/// proposes → the other manager accepts (or rejects) → the commissioner
/// executes (or vetoes). The proposer can cancel while it's still pending.
///
///   proposed → accepted | rejected | cancelled | countered
///   accepted → executed | vetoed
///   rejected / cancelled / vetoed / executed / countered  are terminal
nonisolated enum FantasyTradeStatus: String, Codable, Equatable {
    case proposed, accepted, rejected, cancelled, vetoed, executed, countered

    var isTerminal: Bool {
        switch self {
        case .rejected, .cancelled, .vetoed, .executed, .countered: return true
        case .proposed, .accepted:                                  return false
        }
    }
    var displayName: String {
        switch self {
        case .proposed:  return "Proposed"
        case .accepted:  return "Accepted — awaiting commissioner"
        case .rejected:  return "Rejected"
        case .cancelled: return "Cancelled"
        case .vetoed:    return "Vetoed"
        case .executed:  return "Executed"
        case .countered: return "Countered"
        }
    }
}

/// One proposed trade between two teams IN a league. Stores only canonical player
/// slugs + team ids; the swing math and current rosters are resolved live, so a
/// trade can never carry stale value. Persisted by `FantasyTradeStore`.
nonisolated struct FantasyTrade: Codable, Equatable, Identifiable {
    let id: UUID
    let leagueId: UUID
    /// The proposing team; sends `fromSlugs`, receives `toSlugs`.
    let fromTeamId: UUID
    /// The receiving team; sends `toSlugs`, receives `fromSlugs`.
    let toTeamId: UUID
    /// Players the proposer SENDS (canonical slugs).
    let fromSlugs: [String]
    /// Players the receiver SENDS (canonical slugs).
    let toSlugs: [String]
    /// Non-player assets (draft picks / FAAB) each side includes. Optional so trades
    /// persisted before this feature decode cleanly (missing key → nil → []).
    let fromAssets: [FantasyTradeAsset]?
    let toAssets: [FantasyTradeAsset]?
    var status: FantasyTradeStatus
    var note: String

    /// Non-optional accessors so callers never juggle nil.
    var fromAssetList: [FantasyTradeAsset] { fromAssets ?? [] }
    var toAssetList: [FantasyTradeAsset] { toAssets ?? [] }

    init(id: UUID = UUID(), leagueId: UUID, fromTeamId: UUID, toTeamId: UUID,
         fromSlugs: [String], toSlugs: [String],
         fromAssets: [FantasyTradeAsset]? = nil, toAssets: [FantasyTradeAsset]? = nil,
         status: FantasyTradeStatus = .proposed, note: String = "") {
        self.id = id
        self.leagueId = leagueId
        self.fromTeamId = fromTeamId
        self.toTeamId = toTeamId
        self.fromSlugs = fromSlugs
        self.toSlugs = toSlugs
        self.fromAssets = fromAssets
        self.toAssets = toAssets
        self.status = status
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, leagueId, fromTeamId, toTeamId, fromSlugs, toSlugs, fromAssets, toAssets, status, note
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        leagueId = try c.decode(UUID.self, forKey: .leagueId)
        fromTeamId = try c.decode(UUID.self, forKey: .fromTeamId)
        toTeamId = try c.decode(UUID.self, forKey: .toTeamId)
        fromSlugs = try c.decodeIfPresent([String].self, forKey: .fromSlugs) ?? []
        toSlugs = try c.decodeIfPresent([String].self, forKey: .toSlugs) ?? []
        fromAssets = try c.decodeIfPresent([FantasyTradeAsset].self, forKey: .fromAssets)
        toAssets = try c.decodeIfPresent([FantasyTradeAsset].self, forKey: .toAssets)
        status = try c.decodeIfPresent(FantasyTradeStatus.self, forKey: .status) ?? .proposed
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// Pure trade mechanics: structural validation, roster application, and the
/// status transition guards. Every transition returns a NEW status/roster — the
/// store persists what the engine returns.
nonisolated enum FantasyTradeEngine {

    enum Invalid: Equatable {
        case sameTeam
        case emptySide
        case playerNotOnFromTeam(String)
        case playerNotOnToTeam(String)
        case duplicateAcrossSides(String)
        /// A received player is already on the receiving team's roster (the same
        /// global slug rostered on both teams) — the swap would be a no-op/dup.
        case alreadyOnReceivingTeam(String)
    }

    /// Validate the proposal against the two teams' CURRENT rosters (canonical
    /// slugs). Re-run at execute time — a player may have moved since the propose.
    static func validate(fromTeamId: UUID, toTeamId: UUID,
                         fromSlugs: [String], toSlugs: [String],
                         fromRoster: [String], toRoster: [String]) -> [Invalid] {
        var out: [Invalid] = []
        if fromTeamId == toTeamId { out.append(.sameTeam) }
        if fromSlugs.isEmpty || toSlugs.isEmpty { out.append(.emptySide) }

        let fromSet = Set(fromRoster.map(FantasyValueStore.canonicalSlug))
        let toSet = Set(toRoster.map(FantasyValueStore.canonicalSlug))
        for s in fromSlugs where !fromSet.contains(FantasyValueStore.canonicalSlug(s)) {
            out.append(.playerNotOnFromTeam(s))
        }
        for s in toSlugs where !toSet.contains(FantasyValueStore.canonicalSlug(s)) {
            out.append(.playerNotOnToTeam(s))
        }
        let fromCanon = Set(fromSlugs.map(FantasyValueStore.canonicalSlug))
        for s in toSlugs where fromCanon.contains(FantasyValueStore.canonicalSlug(s)) {
            out.append(.duplicateAcrossSides(s))
        }
        // Receiving-side ownership: a player coming BACK to a team it already
        // rosters (global slug present on both teams) would be a no-op swap.
        for s in toSlugs where fromSet.contains(FantasyValueStore.canonicalSlug(s)) {
            out.append(.alreadyOnReceivingTeam(s))
        }
        for s in fromSlugs where toSet.contains(FantasyValueStore.canonicalSlug(s)) {
            out.append(.alreadyOnReceivingTeam(s))
        }
        return out
    }

    static func isValid(fromTeamId: UUID, toTeamId: UUID,
                        fromSlugs: [String], toSlugs: [String],
                        fromRoster: [String], toRoster: [String]) -> Bool {
        validate(fromTeamId: fromTeamId, toTeamId: toTeamId,
                 fromSlugs: fromSlugs, toSlugs: toSlugs,
                 fromRoster: fromRoster, toRoster: toRoster).isEmpty
    }

    /// A roster after removing `removing` and appending `adding` — canonical +
    /// order-preserving + deduped (a received player already present is not doubled).
    static func resultingRoster(current: [String],
                                removing: [String], adding: [String]) -> [String] {
        let remove = Set(removing.map(FantasyValueStore.canonicalSlug))
        var seen = Set<String>()
        var out: [String] = []
        for s in current.map(FantasyValueStore.canonicalSlug) where !remove.contains(s) {
            if seen.insert(s).inserted { out.append(s) }
        }
        for s in adding.map(FantasyValueStore.canonicalSlug) {
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    // MARK: Status transitions (guarded; nil result = illegal transition)

    static func accepting(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .proposed, to: .accepted) }
    static func rejecting(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .proposed, to: .rejected) }
    static func cancelling(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .proposed, to: .cancelled) }
    /// The recipient answered a proposal with a counter — the original is closed.
    static func countering(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .proposed, to: .countered) }
    static func vetoing(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .accepted, to: .vetoed) }
    static func executing(_ t: FantasyTrade) -> FantasyTrade? { transition(t, from: .accepted, to: .executed) }

    private static func transition(_ t: FantasyTrade,
                                   from: FantasyTradeStatus, to: FantasyTradeStatus) -> FantasyTrade? {
        guard t.status == from else { return nil }
        var next = t
        next.status = to
        return next
    }
}
