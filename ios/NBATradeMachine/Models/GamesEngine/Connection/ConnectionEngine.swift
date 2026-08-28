import Foundation

nonisolated enum ConnectionStatus: String, Codable, Equatable { case building, complete }

nonisolated enum ConnectionError: Error, Equatable {
    /// No pair of endpoints at a BFS-verified target distance could be seeded.
    case noSeedableEndpoints
    /// The submitted id isn't a node in the graph.
    case unknownPlayer
    /// The submitted player is not a teammate of the current chain tail.
    case notTeammate
    /// The player is already in the chain (no reuse).
    case alreadyUsed
    /// The game is already complete.
    case gameComplete
    /// Appending this player would strand the chain: the endpoint is no longer
    /// reachable using only unused players from the new tail. Rejected so the
    /// player never enters an unrecoverable soft-lock (recovery also via undo/reset).
    case deadEnd
    /// Nothing to undo/reset — the chain is already back at `[startId]`.
    case nothingToUndo
}

/// The whole CONNECTION session — a pure value. `chain` starts as `[startId]` and
/// grows one validated teammate link at a time until the tail == `endId`.
/// `optimalLength` is the precomputed BFS shortest-path length (edges) used for
/// optimality scoring.
nonisolated struct ConnectionState: Codable, Equatable {
    let definition: ConnectionDefinition
    let startId: String
    let endId: String
    let optimalLength: Int         // BFS shortest-path length in edges (≥ 1)
    var chain: [String]            // built so far; chain[0] == startId
    var rng: SeededRNG
    var status: ConnectionStatus
    var score: Int

    /// The current end of the chain a new link must be a teammate of.
    var tail: String { chain.last ?? startId }

    /// Links used so far (edges), i.e. chain length − 1.
    var linksUsed: Int { max(chain.count - 1, 0) }
}

nonisolated enum ConnectionEngine {

    /// Seeded endpoints must have a path within this many BFS attempts before we
    /// give up (mirrors the bounded-search discipline).
    static let maxSeedAttempts = 400

    // MARK: - Initialize (BFS-verified reachable endpoints)

    /// Pick two DISTINCT endpoints whose BFS shortest-path length falls in the
    /// preset's `[targetDistanceMin, targetDistanceMax]`, VERIFIED reachable before
    /// presenting (else the puzzle is unwinnable). Deterministic: same seed ⇒ same
    /// endpoints. Throws `.noSeedableEndpoints` past the attempt budget.
    static func initialize(definition: ConnectionDefinition,
                           graph: TeammateGraph,
                           seed: UInt64) throws -> ConnectionState {
        let nodes = graph.nodeIds
        guard nodes.count >= 2 else { throw ConnectionError.noSeedableEndpoints }
        var rng = SeededRNG(seed: seed)

        var attempt = 0
        while attempt < maxSeedAttempts {
            attempt += 1
            let a = nodes[Int(rng.next() % UInt64(nodes.count))]
            let b = nodes[Int(rng.next() % UInt64(nodes.count))]
            guard a != b else { continue }
            guard let len = graph.shortestPathLength(from: a, to: b) else { continue }
            if len >= definition.targetDistanceMin && len <= definition.targetDistanceMax {
                return ConnectionState(definition: definition, startId: a, endId: b,
                                       optimalLength: len, chain: [a], rng: rng,
                                       status: .building, score: 0)
            }
        }
        throw ConnectionError.noSeedableEndpoints
    }

    // MARK: - Append a link

    /// Append one teammate link. Validates: game active, player known to the graph,
    /// not already in the chain, and a teammate of the current tail. Completes when
    /// the appended player IS the endpoint (tail == endId) — scoring optimality.
    ///
    /// Also REJECTS a dead-end append: unless the new player IS the endpoint, the
    /// endpoint must still be reachable from the new tail through only players not
    /// yet in the chain — otherwise the move would soft-lock the puzzle (guarded so
    /// the player is never stranded; undo/reset provide independent recovery).
    static func appendLink(_ state: ConnectionState, playerId: String,
                           graph: TeammateGraph) throws -> ConnectionState {
        guard state.status == .building else { throw ConnectionError.gameComplete }
        guard graph.adjacency[playerId] != nil else { throw ConnectionError.unknownPlayer }
        guard !state.chain.contains(playerId) else { throw ConnectionError.alreadyUsed }
        guard graph.areTeammates(state.tail, playerId) else { throw ConnectionError.notTeammate }

        // Dead-end guard: reaching the endpoint is always fine, but any other move
        // must keep the endpoint reachable on the subgraph of still-unused nodes
        // (plus the new tail + endpoint themselves).
        if playerId != state.endId {
            var usable = Set(graph.nodeIds)
            for used in state.chain { usable.remove(used) }  // interior + start consumed
            usable.insert(playerId)                          // the new tail stays usable
            usable.insert(state.endId)                       // endpoint is a valid terminal
            let sub = graph.restricted(to: usable)
            guard sub.shortestPathLength(from: playerId, to: state.endId) != nil else {
                throw ConnectionError.deadEnd
            }
        }

        var next = state
        next.chain.append(playerId)
        if playerId == state.endId {
            next.status = .complete
            next.score = score(linksUsed: next.linksUsed,
                               optimalLength: state.optimalLength,
                               mode: state.definition.scoreMode)
        }
        return next
    }

    // MARK: - Recovery (undo / reset)

    /// Remove the last interior node, stepping the chain back one link. No-ops-throw
    /// `.nothingToUndo` when the chain is already just `[startId]`. Pure; keeps the
    /// game `.building` with score 0 (only a completed endpoint append scores).
    static func undoLastLink(_ state: ConnectionState) throws -> ConnectionState {
        guard state.chain.count > 1 else { throw ConnectionError.nothingToUndo }
        var next = state
        next.chain.removeLast()
        next.status = .building
        next.score = 0
        return next
    }

    /// Return the chain to `[startId]` — a full restart of the SAME puzzle
    /// (endpoints/optimalLength preserved). Pure; `.building`, score 0. Recovers from
    /// any dead-end regardless of how deep.
    static func reset(_ state: ConnectionState) -> ConnectionState {
        var next = state
        next.chain = [state.startId]
        next.status = .building
        next.score = 0
        return next
    }

    // MARK: - Scoring (reward shorter)

    /// Optimality score: 100 when the chain matches the optimal length, deducting
    /// 15 per extra link past optimal, floored at 1. A player can never BEAT the
    /// BFS optimum (it's the shortest path), so `linksUsed >= optimalLength`.
    static func score(linksUsed: Int, optimalLength: Int, mode: ConnectionScoreMode) -> Int {
        switch mode {
        case .optimality:
            let extra = max(0, linksUsed - optimalLength)
            return max(1, 100 - extra * 15)
        }
    }
}
