import Foundation

nonisolated enum GameParticipantKind: String, Codable, Equatable { case human, cpu }

/// One seat in a game. `id` is the seat index (0-based); rosters/scores are
/// indexed by it.
nonisolated struct GameParticipant: Codable, Equatable, Identifiable {
    let id: Int
    let kind: GameParticipantKind
    let displayName: String
}

/// One filled slot on a roster.
nonisolated struct RosterAssignment: Codable, Equatable {
    let slotId: String
    let entity: GameEntityRecord
}

/// Per-seat consumable special actions (spec §12 subset — Phase 2: rerolls).
nonisolated struct ActionInventory: Codable, Equatable {
    var rerolls: Int
}

nonisolated enum GameStatus: String, Codable, Equatable { case active, complete }

nonisolated enum GameEngineError: Error, Equatable {
    case infeasibleDefinition
    case notYourTurn
    case unknownEntity
    case entityUnavailable
    case notAnOffering
    case slotFilled
    case slotRejectsEntity
    case rosterConstraintViolated
    case cannotAfford
    case noRerollsLeft
    case nothingToReroll
    case incoherentModifiers
}

/// The whole session — a pure value. Codable so a future online session can
/// sync it; Equatable so stores publish cleanly.
nonisolated struct RosterGameState: Codable, Equatable {
    let definition: GameDefinition
    let participants: [GameParticipant]
    let pool: [GameEntityRecord]          // post-entity-constraint pool
    var rosters: [[RosterAssignment]]     // by seat
    var pickedIds: Set<String>            // every id ever picked by ANY seat; consulted only when sharedPool
    let turnSequence: [Int]               // seat per pick, whole game
    var turnIndex: Int
    var offerings: [String]?              // ids offered this turn (randomOffer)
    var rng: SeededRNG
    var status: GameStatus
    var budgets: [Int]?                   // per-seat remaining budget; nil ⟺ no economy (co-seeded with definition.economy at init)
    var actionInventory: [ActionInventory]?   // per-seat special actions; nil when none
}

nonisolated enum RosterConstructionEngine {

    // MARK: - Initialize (spec §13 initializeRosterGame)

    static func initialize(definition: GameDefinition,
                           participants: [GameParticipant],
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> RosterGameState {
        // Slot ids must be unique. GameFeasibility.fill removes a chosen slot by
        // id (`remaining.filter { $0.id != slot.id }`), so duplicate ids would
        // collapse to one — a false-feasible witness that fills fewer slots than
        // declared. No shipped preset has duplicate ids, but GameDefinition is
        // Codable, so guard the decoded/forged path. (Sol review, 2026-08-25.)
        let slotIds = definition.roster.slots.map(\.id)
        guard Set(slotIds).count == slotIds.count else {
            throw GameEngineError.infeasibleDefinition
        }
        let eligible = pool.filter { e in
            definition.entityConstraints.allSatisfy {
                GameConstraintEvaluator.satisfies(e, $0)
            }
        }
        guard GameFeasibility.canComplete(definition: definition,
                                          participantCount: participants.count,
                                          pool: eligible) else {
            throw GameEngineError.infeasibleDefinition
        }
        if let sa = definition.specialActions, sa.rerolls > 0,
           definition.selection.method != .randomOffer {
            throw GameEngineError.incoherentModifiers
        }
        var state = RosterGameState(
            definition: definition,
            participants: participants,
            pool: eligible,
            rosters: Array(repeating: [], count: participants.count),
            pickedIds: [],
            turnSequence: turnSequence(seats: participants.count,
                                       rounds: definition.roster.slots.count,
                                       method: definition.selection.method),
            turnIndex: 0,
            offerings: nil,
            rng: SeededRNG(seed: seed),
            status: .active,
            budgets: definition.economy.map {
                Array(repeating: $0.startingBudget, count: participants.count)
            },
            actionInventory: definition.specialActions.map {
                Array(repeating: ActionInventory(rerolls: $0.rerolls),
                      count: participants.count)
            })
        state = rollOfferingsIfNeeded(state)
        return state
    }

    /// Seat order for every pick. Snake reverses odd rounds; everything else is
    /// round-robin forward. Rounds = slot count (each seat picks once per round).
    static func turnSequence(seats: Int, rounds: Int,
                             method: SelectionMethod) -> [Int] {
        let forward = Array(0..<seats)
        return (0..<rounds).flatMap { r -> [Int] in
            (method == .snake && r % 2 == 1) ? forward.reversed() : forward
        }
    }

    static func currentSeat(_ state: RosterGameState) -> Int? {
        guard state.status == .active,
              state.turnIndex < state.turnSequence.count else { return nil }
        return state.turnSequence[state.turnIndex]
    }

    // MARK: - Turn info (spec §13 beginTurn)

    /// Open slots on `seat`'s roster that accept `entity`.
    static func validSlots(_ state: RosterGameState, seat: Int,
                           entity: GameEntityRecord) -> [RosterSlot] {
        guard state.rosters.indices.contains(seat) else { return [] }
        let filled = Set(state.rosters[seat].map(\.slotId))
        return state.definition.roster.slots.filter {
            !filled.contains($0.id) && $0.accepts(entity)
        }
    }

    /// Entities `seat` may legally pick right now: still available (shared-pool
    /// removal + own-roster dedup), inside this turn's offerings when limited,
    /// accepted by at least one open slot, and roster-constraint clean.
    /// Meaningful only for the CURRENT seat (offerings belong to the live turn);
    /// `seat` must be a valid index. An empty result for the current seat means
    /// the game is cornered — the session driver ends the game honestly.
    static func eligibleEntities(_ state: RosterGameState, seat: Int) -> [GameEntityRecord] {
        guard state.rosters.indices.contains(seat) else { return [] }
        let roster = state.rosters[seat].map(\.entity)
        let ownIds = Set(roster.map(\.id))
        return state.pool.filter { e in
            if state.definition.selection.sharedPool && state.pickedIds.contains(e.id) {
                return false
            }
            if ownIds.contains(e.id) { return false }
            if let econ = state.definition.economy,
               let budget = state.budgets?[seat], econ.price(e) > budget {
                return false
            }
            if let offered = state.offerings, !offered.contains(e.id) { return false }
            guard !validSlots(state, seat: seat, entity: e).isEmpty else { return false }
            return GameConstraintEvaluator.allowsPick(
                roster: roster, candidate: e,
                constraints: state.definition.rosterConstraints)
        }
    }

    // MARK: - Actions (spec §13 submitRosterSelection)

    static func submitPick(_ state: RosterGameState, seat: Int,
                           entityId: String, slotId: String) throws -> RosterGameState {
        guard currentSeat(state) == seat else { throw GameEngineError.notYourTurn }
        guard let entity = state.pool.first(where: { $0.id == entityId }) else {
            throw GameEngineError.unknownEntity
        }
        if let offered = state.offerings, !offered.contains(entityId) {
            throw GameEngineError.notAnOffering
        }
        let roster = state.rosters[seat].map(\.entity)
        let takenFromShared = state.definition.selection.sharedPool
            && state.pickedIds.contains(entityId)
        if takenFromShared || roster.contains(where: { $0.id == entityId }) {
            throw GameEngineError.entityUnavailable
        }
        // An unknown slotId also lands here — from the picker UI both read as
        // "that slot isn't open".
        guard let slot = state.definition.roster.slots.first(where: { $0.id == slotId }),
              !state.rosters[seat].contains(where: { $0.slotId == slotId }) else {
            throw GameEngineError.slotFilled
        }
        guard slot.accepts(entity) else { throw GameEngineError.slotRejectsEntity }
        guard GameConstraintEvaluator.allowsPick(
            roster: roster, candidate: entity,
            constraints: state.definition.rosterConstraints) else {
            throw GameEngineError.rosterConstraintViolated
        }
        let cost: Int
        if let econ = state.definition.economy {
            cost = econ.price(entity)
            guard let budget = state.budgets?[seat], cost <= budget else {
                throw GameEngineError.cannotAfford
            }
        } else {
            cost = 0
        }

        var next = state
        next.rosters[seat].append(RosterAssignment(slotId: slotId, entity: entity))
        next.pickedIds.insert(entityId)
        if state.definition.economy != nil { next.budgets?[seat] -= cost }
        next.turnIndex += 1
        next.offerings = nil
        if next.turnIndex >= next.turnSequence.count {
            next.status = .complete
        } else {
            next = rollOfferingsIfNeeded(next)
        }
        return next
    }

    /// Re-roll the current seat's offering, consuming one reroll. Does NOT
    /// advance the turn. Only valid on an offering-based game with a live
    /// offering and rerolls remaining.
    static func reroll(_ state: RosterGameState, seat: Int) throws -> RosterGameState {
        guard currentSeat(state) == seat else { throw GameEngineError.notYourTurn }
        guard state.offerings != nil else { throw GameEngineError.nothingToReroll }
        guard var inv = state.actionInventory?[seat], inv.rerolls > 0 else {
            throw GameEngineError.noRerollsLeft
        }
        var next = state
        inv.rerolls -= 1
        next.actionInventory?[seat] = inv
        next.offerings = nil                 // rollOfferingsIfNeeded re-draws from scratch
        return rollOfferingsIfNeeded(next)   // advances rng → a fresh offering
    }

    /// randomOffer: draw `offeringsPerTurn` ids for the upcoming turn from the
    /// entities that seat could legally pick, deterministically in `rng`. If the
    /// legal set is smaller than the request, offer what exists; if it is empty
    /// (unreachable for feasibility-checked presets, but constraints can corner
    /// a game), finish the game honestly instead of deadlocking. A nil or
    /// non-positive `offeringsPerTurn` disables the offer limit (defensive —
    /// presets always set a positive count).
    static func rollOfferingsIfNeeded(_ state: RosterGameState) -> RosterGameState {
        guard state.definition.selection.method == .randomOffer,
              let n = state.definition.selection.offeringsPerTurn, n > 0,
              let seat = currentSeat(state) else { return state }
        var next = state
        next.offerings = nil    // candidates must not be limited by a stale offer
        let candidates = eligibleEntities(next, seat: seat)
        guard !candidates.isEmpty else {
            next.status = .complete
            return next
        }
        var rng = next.rng
        next.offerings = candidates.shuffled(using: &rng).prefix(n).map(\.id)
        next.rng = rng
        return next
    }
}

/// A finished game (spec §25): the engine builds it; scoring stays out of the
/// interaction loop so a future evaluator swap never touches the engine.
nonisolated struct GameResult: Codable, Equatable {
    let rosters: [[RosterAssignment]]
    let scores: [Double]?     // by seat; nil when scoring == .none
    let winnerSeat: Int?      // nil for solo games, exact ties, or scoring == .none
}

nonisolated extension RosterConstructionEngine {

    static func buildResult(_ state: RosterGameState) -> GameResult {
        let scores: [Double]?
        switch state.definition.scoring {
        case .none:
            scores = nil
        case .teamRating:
            scores = state.rosters.map { $0.reduce(0) { $0 + $1.entity.rating } }
        }
        let winner: Int? = {
            guard let scores, state.participants.count > 1,
                  let best = scores.max() else { return nil }
            // exact == is safe: teamRating sums identical rating multisets
            // bit-identically. Revisit if scoring gains FP-reordering (weighted
            // sums, averages) where should-tie sums can differ by an ULP.
            let leaders = scores.indices.filter { scores[$0] == best }
            return leaders.count == 1 ? leaders[0] : nil
        }()
        return GameResult(rosters: state.rosters, scores: scores, winnerSeat: winner)
    }
}
