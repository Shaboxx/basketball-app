import Foundation

nonisolated enum BracketStatus: String, Codable, Equatable { case playing, complete }

nonisolated enum BracketError: Error, Equatable {
    case invalidFieldSize          // not a power-of-two in {4,8,16}
    case notEnoughEntities         // fewer than fieldSize distinct entities
    case notInMatchup             // winnerId isn't one of the current matchup's two sides
    case unknownEntity            // winnerId isn't any seed
    case outOfOrder               // advancing while the game is already complete
    case complete                 // acting on a finished bracket
}

/// The whole BRACKET session — a pure value. Construct ONLY via
/// `BracketEngine.initialize` (seed order + distinctness invariants are
/// established there). `picks` are advanced-winner ids in matchup order
/// (round-major): the first `fieldSize/2` picks are round 0, the next
/// `fieldSize/4` are round 1, … A decoded blob that bypasses initialize is the
/// caller's risk; the scorer defends against a malformed state.
nonisolated struct BracketState: Codable, Equatable {
    let definition: BracketDefinition
    let seeds: [GameEntityRecord]     // fieldSize entities in seeded bracket order
    var picks: [String]               // advanced-winner ids, matchup order (round-major)
    var rng: SeededRNG
    var status: BracketStatus

    func entity(_ id: String) -> GameEntityRecord? { seeds.first { $0.id == id } }
}

/// Pure nonisolated BRACKET engine. Single-elimination: each `advance` records
/// the human's chosen winner for the current matchup; the field halves every
/// round until one champion remains. Round progression is DERIVED from `picks`
/// (no stored round pointer), so the state stays minimal and replay is exact.
nonisolated enum BracketEngine {

    /// Valid single-elimination field sizes (powers of two, spec §14 §85).
    static let validFieldSizes: Set<Int> = [4, 8, 16]

    static func initialize(definition: BracketDefinition,
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> BracketState {
        let n = definition.fieldSize
        guard validFieldSizes.contains(n) else { throw BracketError.invalidFieldSize }
        // Dedup by id (a duplicate would corrupt matchup lookups).
        var seen = Set<String>()
        let eligible = pool.filter { e in
            definition.entityConstraints.allSatisfy {
                GameConstraintEvaluator.satisfies(e, $0)
            }
        }.filter { seen.insert($0.id).inserted }
        guard eligible.count >= n else { throw BracketError.notEnoughEntities }

        var rng = SeededRNG(seed: seed)
        let field: [GameEntityRecord]
        if definition.seedByRating {
            // Top-n by rating (ties by id asc — deterministic like the classifier).
            field = Array(eligible.sorted {
                $0.rating != $1.rating ? $0.rating > $1.rating : $0.id < $1.id
            }.prefix(n))
        } else {
            field = Array(eligible.shuffled(using: &rng).prefix(n))
        }

        let seeds = definition.seedByRating ? seedOrder(field) : field
        return BracketState(definition: definition, seeds: seeds,
                            picks: [], rng: rng, status: .playing)
    }

    /// Standard single-elimination seed order so the top seeds meet last:
    /// 1-vs-N, then the winner meets the winner of 2-vs-(N-1), etc. Placement is
    /// the classic bracket recursion. `field` is sorted best→worst (index 0 = #1
    /// seed). Returns the entities arranged so adjacent pairs (0,1)(2,3)… are the
    /// round-0 matchups.
    static func seedOrder(_ field: [GameEntityRecord]) -> [GameEntityRecord] {
        let n = field.count
        // Seed positions: for a bracket of size n, position list is built by the
        // standard bracket-slot recursion. positions[i] = the 1-based seed that
        // belongs in bracket slot i.
        var positions = [1]
        while positions.count < n {
            let rounds = positions.count * 2
            var next: [Int] = []
            for p in positions {
                next.append(p)
                next.append(rounds + 1 - p)
            }
            positions = next
        }
        // positions is 1-based seed numbers in slot order; map to 0-based field.
        return positions.map { field[$0 - 1] }
    }

    // MARK: - Derived progression

    /// The winners of a given round, in matchup order, computed from `picks`.
    /// Round 0's participants are the seeds; each later round's participants are
    /// the previous round's picked winners.
    static func participants(_ state: BracketState, round: Int) -> [GameEntityRecord] {
        if round == 0 { return state.seeds }
        let prevWinners = winners(state, round: round - 1)
        return prevWinners
    }

    /// The picked winners of a round as entities (only the ones already chosen).
    static func winners(_ state: BracketState, round: Int) -> [GameEntityRecord] {
        let (start, count) = pickRange(fieldSize: state.definition.fieldSize, round: round)
        let end = min(state.picks.count, start + count)
        guard start < end else { return [] }
        return state.picks[start..<end].compactMap { state.entity($0) }
    }

    /// [startIndex, matchupCount) into `picks` for a round (round-major layout).
    static func pickRange(fieldSize: Int, round: Int) -> (start: Int, count: Int) {
        var start = 0
        var matchups = fieldSize / 2
        var r = 0
        while r < round {
            start += matchups
            matchups /= 2
            r += 1
        }
        return (start, matchups)
    }

    /// Total number of matchups in the whole bracket = fieldSize - 1.
    static func totalMatchups(fieldSize: Int) -> Int { fieldSize - 1 }

    /// The 0-based index (into `picks`) of the matchup awaiting a decision, or nil
    /// when the bracket is finished.
    static func currentMatchupIndex(_ state: BracketState) -> Int? {
        guard state.status == .playing else { return nil }
        let total = totalMatchups(fieldSize: state.definition.fieldSize)
        return state.picks.count < total ? state.picks.count : nil
    }

    /// The 0-based round of the current matchup, or nil when finished.
    static func currentRound(_ state: BracketState) -> Int? {
        guard let idx = currentMatchupIndex(state) else { return nil }
        var start = 0
        var matchups = state.definition.fieldSize / 2
        var round = 0
        while idx >= start + matchups {
            start += matchups
            matchups /= 2
            round += 1
        }
        return round
    }

    /// The two entities of the current matchup (left, right), or nil when finished.
    static func currentMatchup(_ state: BracketState) -> (GameEntityRecord, GameEntityRecord)? {
        guard let idx = currentMatchupIndex(state),
              let round = currentRound(state) else { return nil }
        let (start, _) = pickRange(fieldSize: state.definition.fieldSize, round: round)
        let localIndex = idx - start
        // This round's participant list: for round 0 the seeds, else prior winners.
        // The current matchup uses positions (2*localIndex, 2*localIndex+1).
        let field = participants(state, round: round)
        let a = 2 * localIndex
        let b = a + 1
        guard field.indices.contains(a), field.indices.contains(b) else { return nil }
        return (field[a], field[b])
    }

    // MARK: - Advance

    /// Record `winnerId` as the winner of the current matchup and progress. Throws
    /// if the bracket is finished (`complete`), `winnerId` isn't a seed
    /// (`unknownEntity`), or it isn't one of the current matchup's two sides
    /// (`notInMatchup`).
    static func advance(_ state: BracketState, winnerId: String) throws -> BracketState {
        guard state.status == .playing else { throw BracketError.complete }
        guard state.entity(winnerId) != nil else { throw BracketError.unknownEntity }
        guard let (a, b) = currentMatchup(state) else { throw BracketError.outOfOrder }
        guard winnerId == a.id || winnerId == b.id else { throw BracketError.notInMatchup }
        var next = state
        next.picks.append(winnerId)
        if next.picks.count >= totalMatchups(fieldSize: next.definition.fieldSize) {
            next.status = .complete
        }
        return next
    }
}
