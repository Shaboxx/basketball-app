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
    var pickedIds: Set<String>            // gone from the shared pool
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

    /// Placeholder — implemented with randomOffer in Task 8. Kept here so
    /// initialize compiles from day one.
    static func rollOfferingsIfNeeded(_ state: RosterGameState) -> RosterGameState {
        state
    }
}
