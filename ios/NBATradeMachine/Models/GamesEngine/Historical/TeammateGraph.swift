import Foundation

/// The teammate adjacency graph decoded from `teammate-graph.json`
/// (`{"_meta":…,"players":{"<nbaId>":{"teammates":{"<id>":[seasons]},"franchises":[tricodes]}}}`).
/// Node keys are numeric nba ids as strings — the SAME `id` as
/// `HistoricalPlayerEntity`, so CONNECTION's answer resolution joins cleanly.
///
/// Pure value + `Sendable` so the 10MB decode can run off the main actor and the
/// built graph returns to the main actor without a data-race diagnostic.
///
/// Caveat (documented): a traded player's edges reflect his aggregate/last team
/// for a season only (see `_meta.note`) — some teammate links are approximate,
/// acceptable for a trivia game.
nonisolated struct TeammateGraph: Codable, Equatable, Sendable {
    /// nbaId → sorted list of teammate nbaIds (deterministic neighbor order).
    let adjacency: [String: [String]]
    /// nbaId → franchise tricodes (informational; cross-checks GRID franchises).
    let franchises: [String: [String]]

    // MARK: - Decode

    /// Raw JSON shapes — decoded then transformed into the flat adjacency.
    private struct RawFile: Codable {
        let players: [String: RawNode]
    }
    private struct RawNode: Codable {
        let teammates: [String: [String]]?
        let franchises: [String]?
    }

    /// Decode + build adjacency from a Data blob. The adjacency is SYMMETRIZED
    /// (every A→B also implies B→A) so BFS operates on exactly the same undirected
    /// relation gameplay's symmetric `areTeammates` exposes — otherwise a
    /// directed-only edge would let `shortestPath`/`shortestPathLength` disagree with
    /// what the player can actually build, mis-scoring optimality. Neighbor lists are
    /// sorted by id for reproducible BFS. Pure — testable without Bundle/Firestore.
    static func load(from data: Data) throws -> TeammateGraph {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        var franchises: [String: [String]] = [:]
        franchises.reserveCapacity(raw.players.count)
        // Collect directed edges + ensure every node exists as a key (isolated nodes
        // keep an empty neighbor list).
        var neighborSets: [String: Set<String>] = [:]
        neighborSets.reserveCapacity(raw.players.count)
        for (id, node) in raw.players {
            let teammateIds: [String] = node.teammates.map { Array($0.keys) } ?? []
            neighborSets[id, default: []].formUnion(teammateIds)
            // Symmetrize: mirror each edge back so the relation is undirected.
            for t in teammateIds {
                neighborSets[t, default: []].insert(id)
            }
            franchises[id] = node.franchises ?? []
        }
        var adjacency: [String: [String]] = [:]
        adjacency.reserveCapacity(neighborSets.count)
        for (id, set) in neighborSets {
            adjacency[id] = set.sorted()
        }
        return TeammateGraph(adjacency: adjacency, franchises: franchises)
    }

    // MARK: - Subgraph

    /// The node-induced subgraph over `allowed` ids: drops any node not in
    /// `allowed` and prunes edges to dropped nodes. Used by CONNECTION to build a
    /// puzzle whose EVERY node is a name-searchable distinct player (the raw graph
    /// carries ~1200 ineligible nodes not in the answer index, which would be
    /// unsearchable). Franchises are carried through for retained nodes. Neighbor
    /// order stays sorted → BFS stays deterministic.
    func restricted(to allowed: Set<String>) -> TeammateGraph {
        var neighborSets: [String: Set<String>] = [:]
        var fran: [String: [String]] = [:]
        for (id, neighbors) in adjacency where allowed.contains(id) {
            let kept = neighbors.filter { allowed.contains($0) }
            neighborSets[id, default: []].formUnion(kept)
            // Re-symmetrize the induced subgraph so BFS matches `areTeammates`.
            for n in kept { neighborSets[n, default: []].insert(id) }
            fran[id] = franchises[id] ?? []
        }
        var adj: [String: [String]] = [:]
        for (id, set) in neighborSets { adj[id] = set.sorted() }
        return TeammateGraph(adjacency: adj, franchises: fran)
    }

    // MARK: - Queries

    /// All node ids, sorted — a reproducible enumeration for seeded endpoint picks.
    var nodeIds: [String] { adjacency.keys.sorted() }

    /// True when `a` and `b` share a teammate edge. O(neighbors). Symmetric in the
    /// source data, but we check both directions defensively.
    func areTeammates(_ a: String, _ b: String) -> Bool {
        (adjacency[a]?.contains(b) ?? false) || (adjacency[b]?.contains(a) ?? false)
    }

    /// Sorted neighbor ids of `id` (empty if unknown).
    func neighbors(of id: String) -> [String] { adjacency[id] ?? [] }

    /// Deterministic BFS shortest path from `from` to `to` (inclusive endpoints).
    /// Returns nil when unreachable or an endpoint is unknown. Neighbor order is
    /// the sorted adjacency list, so the discovered path is reproducible.
    func shortestPath(from: String, to: String) -> [String]? {
        guard adjacency[from] != nil, adjacency[to] != nil else { return nil }
        if from == to { return [from] }
        var visited: Set<String> = [from]
        var queue: [String] = [from]
        var head = 0
        var parent: [String: String] = [:]
        while head < queue.count {
            let node = queue[head]; head += 1
            for next in neighbors(of: node) where !visited.contains(next) {
                visited.insert(next)
                parent[next] = node
                if next == to { return reconstruct(from: from, to: to, parent: parent) }
                queue.append(next)
            }
        }
        return nil
    }

    /// The shortest-path LENGTH in edges (nodes − 1), or nil if unreachable.
    func shortestPathLength(from: String, to: String) -> Int? {
        shortestPath(from: from, to: to).map { $0.count - 1 }
    }

    private func reconstruct(from: String, to: String, parent: [String: String]) -> [String] {
        var path = [to]
        var cur = to
        while cur != from, let p = parent[cur] {
            path.append(p)
            cur = p
        }
        return path.reversed()
    }
}
