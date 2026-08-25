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
}

nonisolated enum RosterConstructionEngine {

    // MARK: - Initialize (spec §13 initializeRosterGame)

    static func initialize(definition: GameDefinition,
                           participants: [GameParticipant],
                           pool: [GameEntityRecord],
                           seed: UInt64) throws -> RosterGameState {
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
            status: .active)
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
        let roster = state.rosters[seat].map(\.entity)
        let ownIds = Set(roster.map(\.id))
        return state.pool.filter { e in
            if state.definition.selection.sharedPool && state.pickedIds.contains(e.id) {
                return false
            }
            if ownIds.contains(e.id) { return false }
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

        var next = state
        next.rosters[seat].append(RosterAssignment(slotId: slotId, entity: entity))
        next.pickedIds.insert(entityId)
        next.turnIndex += 1
        next.offerings = nil
        if next.turnIndex >= next.turnSequence.count {
            next.status = .complete
        } else {
            next = rollOfferingsIfNeeded(next)
        }
        return next
    }

    /// Placeholder — implemented with randomOffer in Task 8. Kept here so
    /// initialize compiles from day one.
    static func rollOfferingsIfNeeded(_ state: RosterGameState) -> RosterGameState {
        state
    }
}
