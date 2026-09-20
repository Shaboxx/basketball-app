import XCTest
@testable import BasketballOffline

/// Phase-6 T7: seeded endpoints at a BFS-verified target distance, appendLink
/// validation (teammate-of-tail, reuse rejection, reach-endpoint completion),
/// optimality scoring (reward shorter), determinism.
final class ConnectionEngineTests: XCTestCase {

    /// A path graph 1—2—3—4—5 (each adjacent pair are teammates), plus 6—7 as a
    /// separate component so some pairs are unreachable.
    private func graph() throws -> TeammateGraph {
        let json = """
        {"_meta":{"schemaVersion":1},
         "players":{
           "1":{"franchises":["A"],"teammates":{"2":["2000-01"]}},
           "2":{"franchises":["A"],"teammates":{"1":["2000-01"],"3":["2001-02"]}},
           "3":{"franchises":["B"],"teammates":{"2":["2001-02"],"4":["2002-03"]}},
           "4":{"franchises":["B"],"teammates":{"3":["2002-03"],"5":["2003-04"]}},
           "5":{"franchises":["C"],"teammates":{"4":["2003-04"]}},
           "6":{"franchises":["D"],"teammates":{"7":["2010-11"]}},
           "7":{"franchises":["D"],"teammates":{"6":["2010-11"]}}
         }}
        """
        return try TeammateGraph.load(from: Data(json.utf8))
    }

    private let def = ConnectionDefinition(id: "six-degrees", title: "SD",
                                           targetDistanceMin: 2, targetDistanceMax: 4)

    func testInitializeSeedsReachableEndpointsAtTargetDistance() throws {
        let g = try graph()
        // Try many seeds; every produced state must have a BFS-verified path whose
        // length is in [2,4] and equals optimalLength.
        for seed in UInt64(0)..<50 {
            guard let state = try? ConnectionEngine.initialize(definition: def, graph: g, seed: seed)
            else { continue }
            XCTAssertNotEqual(state.startId, state.endId)
            let realLen = g.shortestPathLength(from: state.startId, to: state.endId)
            XCTAssertEqual(realLen, state.optimalLength)
            XCTAssertGreaterThanOrEqual(state.optimalLength, 2)
            XCTAssertLessThanOrEqual(state.optimalLength, 4)
            XCTAssertEqual(state.chain, [state.startId])
        }
    }

    func testDeterministicEndpointsForSameSeed() throws {
        let g = try graph()
        let a = try ConnectionEngine.initialize(definition: def, graph: g, seed: 123)
        let b = try ConnectionEngine.initialize(definition: def, graph: g, seed: 123)
        XCTAssertEqual(a.startId, b.startId)
        XCTAssertEqual(a.endId, b.endId)
    }

    func testThrowsWhenNoSeedablePair() throws {
        // A graph where the only reachable non-self distances are 1 → never in [2,4].
        let json = """
        {"_meta":{"schemaVersion":1},
         "players":{
           "1":{"franchises":["A"],"teammates":{"2":["x"]}},
           "2":{"franchises":["A"],"teammates":{"1":["x"]}}
         }}
        """
        let g = try TeammateGraph.load(from: Data(json.utf8))
        XCTAssertThrowsError(try ConnectionEngine.initialize(definition: def, graph: g, seed: 1)) {
            XCTAssertEqual($0 as? ConnectionError, .noSeedableEndpoints)
        }
    }

    func testAppendValidTeammateAdvancesChain() throws {
        let g = try graph()
        // Force endpoints 1 → 3 (distance 2). Build state manually for determinism.
        let state = ConnectionState(definition: def, startId: "1", endId: "3",
                                    optimalLength: 2, chain: ["1"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        let s1 = try ConnectionEngine.appendLink(state, playerId: "2", graph: g)
        XCTAssertEqual(s1.chain, ["1", "2"])
        XCTAssertEqual(s1.status, .building)
        // Reaching the endpoint completes + scores optimality (2 links == optimal → 100).
        let s2 = try ConnectionEngine.appendLink(s1, playerId: "3", graph: g)
        XCTAssertEqual(s2.chain, ["1", "2", "3"])
        XCTAssertEqual(s2.status, .complete)
        XCTAssertEqual(s2.score, 100)
    }

    func testAppendRejectsNonTeammate() throws {
        let g = try graph()
        let state = ConnectionState(definition: def, startId: "1", endId: "5",
                                    optimalLength: 4, chain: ["1"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        // 3 is NOT a teammate of 1.
        XCTAssertThrowsError(try ConnectionEngine.appendLink(state, playerId: "3", graph: g)) {
            XCTAssertEqual($0 as? ConnectionError, .notTeammate)
        }
    }

    func testAppendRejectsReuseAndUnknown() throws {
        let g = try graph()
        var state = ConnectionState(definition: def, startId: "1", endId: "5",
                                    optimalLength: 4, chain: ["1"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        state = try ConnectionEngine.appendLink(state, playerId: "2", graph: g)
        // Reuse 1 (already in chain) — 1 IS a teammate of tail 2, but already used.
        XCTAssertThrowsError(try ConnectionEngine.appendLink(state, playerId: "1", graph: g)) {
            XCTAssertEqual($0 as? ConnectionError, .alreadyUsed)
        }
        // Unknown node.
        XCTAssertThrowsError(try ConnectionEngine.appendLink(state, playerId: "999", graph: g)) {
            XCTAssertEqual($0 as? ConnectionError, .unknownPlayer)
        }
    }

    func testOptimalityRewardsShorter() {
        // Optimal 2: a 2-link chain → 100; 3 links → 85; 5 links → 55.
        XCTAssertEqual(ConnectionEngine.score(linksUsed: 2, optimalLength: 2, mode: .optimality), 100)
        XCTAssertEqual(ConnectionEngine.score(linksUsed: 3, optimalLength: 2, mode: .optimality), 85)
        XCTAssertEqual(ConnectionEngine.score(linksUsed: 5, optimalLength: 2, mode: .optimality), 55)
        // Floors at 1 for a very long chain.
        XCTAssertEqual(ConnectionEngine.score(linksUsed: 20, optimalLength: 2, mode: .optimality), 1)
    }

    // MARK: - FIX 2: dead-end recovery (undo / reset)

    /// From a constructed dead-end (a chain built into a stub where the endpoint is
    /// no longer reachable through unused nodes), `undoLastLink` steps back to a
    /// playable state and `reset` returns the chain to `[startId]`.
    func testUndoAndResetRecoverFromDeadEnd() throws {
        let g = try graph()
        // On the path 1—2—3—4—5, seed endpoints 1 → 5 (optimal 4). Manually build a
        // chain that has wandered: 1 → 2 → 3. This is still recoverable, but exercise
        // both recovery ops.
        var state = ConnectionState(definition: def, startId: "1", endId: "5",
                                    optimalLength: 4, chain: ["1", "2", "3"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        // Undo drops the last interior node → chain back to [1,2], still playable.
        state = try ConnectionEngine.undoLastLink(state)
        XCTAssertEqual(state.chain, ["1", "2"])
        XCTAssertEqual(state.status, .building)
        // Reset returns to just the start.
        let cleared = ConnectionEngine.reset(state)
        XCTAssertEqual(cleared.chain, ["1"])
        XCTAssertEqual(cleared.status, .building)
        XCTAssertEqual(cleared.score, 0)
        // From the fresh [startId] a valid teammate append works again.
        let replay = try ConnectionEngine.appendLink(cleared, playerId: "2", graph: g)
        XCTAssertEqual(replay.chain, ["1", "2"])
    }

    func testUndoAtStartThrowsNothingToUndo() {
        let state = ConnectionState(definition: def, startId: "1", endId: "5",
                                    optimalLength: 4, chain: ["1"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        XCTAssertThrowsError(try ConnectionEngine.undoLastLink(state)) {
            XCTAssertEqual($0 as? ConnectionError, .nothingToUndo)
        }
    }

    /// `appendLink` rejects a move that would strand the endpoint. Using the two-
    /// component graph, seed 1 → 5 (reachable via the 1–5 path), then try to walk
    /// into the disconnected {6,7} island — that append is a dead-end (5 unreachable
    /// from 6), so it must throw `.deadEnd`. Since 6 isn't a teammate of 1, use a
    /// tail where it would otherwise be legal: append checks reachability, not just
    /// adjacency, so we verify a legal-but-stranding move on a purpose-built graph.
    func testAppendRejectsDeadEndMove() throws {
        // Graph: start 1 — 2 — end 3, and 2 — 4 (a spur to a leaf 4 with no route to 3).
        let json = """
        {"_meta":{"schemaVersion":1},
         "players":{
           "1":{"franchises":["A"],"teammates":{"2":["x"]}},
           "2":{"franchises":["A"],"teammates":{"1":["x"],"3":["y"],"4":["z"]}},
           "3":{"franchises":["B"],"teammates":{"2":["y"]}},
           "4":{"franchises":["C"],"teammates":{"2":["z"]}}
         }}
        """
        let g = try TeammateGraph.load(from: Data(json.utf8))
        // Chain 1 → 2 (tail 2). Appending 4 leaves the endpoint 3 reachable ONLY
        // through 2, which is now used → 4 is a dead-end.
        let state = ConnectionState(definition: def, startId: "1", endId: "3",
                                    optimalLength: 2, chain: ["1", "2"],
                                    rng: SeededRNG(seed: 1), status: .building, score: 0)
        XCTAssertThrowsError(try ConnectionEngine.appendLink(state, playerId: "4", graph: g)) {
            XCTAssertEqual($0 as? ConnectionError, .deadEnd)
        }
        // The correct move (append the endpoint 3) is still accepted.
        let done = try ConnectionEngine.appendLink(state, playerId: "3", graph: g)
        XCTAssertEqual(done.status, .complete)
    }

    func testCompleteBlocksFurtherAppends() throws {
        let g = try graph()
        let state = ConnectionState(definition: def, startId: "1", endId: "2",
                                    optimalLength: 1, chain: ["1"],
                                    rng: SeededRNG(seed: 1), status: .complete, score: 100)
        XCTAssertThrowsError(try ConnectionEngine.appendLink(state, playerId: "2", graph: g)) {
            XCTAssertEqual($0 as? ConnectionError, .gameComplete)
        }
    }
}
