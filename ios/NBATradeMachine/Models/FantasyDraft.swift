import Foundation

/// One draft selection. `overall` and `round` are 1-based.
nonisolated struct FantasyDraftPick: Codable, Equatable, Hashable {
    let overall: Int
    let round: Int
    let teamId: UUID
    let slug: String          // canonical player slug
}

nonisolated enum FantasyDraftStatus: String, Codable {
    case inProgress, complete, applied
}

/// A league's draft: a fixed round-1 team order (later rounds snake), a round
/// count, and the picks made so far. Persisted by `FantasyDraftStore` (one
/// draft per league); `applied` means the results were written onto the teams.
nonisolated struct FantasyDraft: Codable, Equatable, Identifiable {
    let id: UUID
    let leagueId: UUID
    let order: [UUID]
    let rounds: Int
    var picks: [FantasyDraftPick]
    var status: FantasyDraftStatus

    init(id: UUID = UUID(), leagueId: UUID, order: [UUID], rounds: Int,
         picks: [FantasyDraftPick] = [], status: FantasyDraftStatus = .inProgress) {
        self.id = id
        self.leagueId = leagueId
        self.order = order
        self.rounds = rounds
        self.picks = picks
        self.status = status
    }
}

/// Pure snake-draft mechanics: sequencing, validation, pick/undo transitions,
/// and the final roster mapping. Every transition returns a NEW draft value —
/// the store persists what the engine returns.
nonisolated enum FantasyDraftEngine {

    enum PickError: Error, Equatable {
        case notInProgress
        case alreadyTaken
        case draftFull
    }

    static func totalPicks(_ draft: FantasyDraft) -> Int {
        draft.order.count * draft.rounds
    }

    /// The full snake sequence: odd rounds in order, even rounds reversed.
    static func pickSequence(order: [UUID], rounds: Int) -> [UUID] {
        guard !order.isEmpty, rounds > 0 else { return [] }
        var seq: [UUID] = []
        for r in 1...rounds {
            seq.append(contentsOf: r.isMultiple(of: 2) ? order.reversed() : order)
        }
        return seq
    }

    /// 1-based round for a 1-based overall pick.
    static func round(forOverall overall: Int, teams: Int) -> Int {
        guard teams > 0, overall > 0 else { return 0 }
        return (overall - 1) / teams + 1
    }

    /// The team making the NEXT pick; nil once every slot is filled.
    static func onTheClock(_ draft: FantasyDraft) -> UUID? {
        let seq = pickSequence(order: draft.order, rounds: draft.rounds)
        guard draft.picks.count < seq.count else { return nil }
        return seq[draft.picks.count]
    }

    static func takenSlugs(_ draft: FantasyDraft) -> Set<String> {
        Set(draft.picks.map(\.slug))
    }

    /// Validate + apply one pick. Marks the draft complete when the last slot fills.
    static func makingPick(_ draft: FantasyDraft, slug: String) -> Result<FantasyDraft, PickError> {
        guard draft.status == .inProgress else { return .failure(.notInProgress) }
        let canon = FantasyValueStore.canonicalSlug(slug)
        guard !takenSlugs(draft).contains(canon) else { return .failure(.alreadyTaken) }
        guard let team = onTheClock(draft) else { return .failure(.draftFull) }

        var next = draft
        let overall = draft.picks.count + 1
        next.picks.append(FantasyDraftPick(
            overall: overall,
            round: round(forOverall: overall, teams: draft.order.count),
            teamId: team, slug: canon))
        if next.picks.count == totalPicks(next) { next.status = .complete }
        return .success(next)
    }

    /// Revert the most recent pick (commissioner control). A completed-but-not-
    /// applied draft reopens; an APPLIED draft is immutable; empty is a no-op.
    static func undoingLastPick(_ draft: FantasyDraft) -> FantasyDraft {
        guard draft.status != .applied, !draft.picks.isEmpty else { return draft }
        var next = draft
        next.picks.removeLast()
        next.status = .inProgress
        return next
    }

    /// teamId → drafted slugs in pick order (the rosters an apply writes).
    static func rosters(_ draft: FantasyDraft) -> [UUID: [String]] {
        var out: [UUID: [String]] = [:]
        for pick in draft.picks {
            out[pick.teamId, default: []].append(pick.slug)
        }
        return out
    }

    /// Best available by the league's format value: the first not-taken player
    /// in value order (auto-pick).
    static func bestAvailable(pool: [Player],
                              values: [String: FantasyValue],
                              format: FantasyFormat,
                              taken: Set<String>) -> Player? {
        FantasyPlayerOrdering.byValue(pool, values: values, format: format)
            .first { !taken.contains(FantasyValueStore.canonicalSlug($0.slug)) }
    }
}
