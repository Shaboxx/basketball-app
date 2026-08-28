import Foundation

nonisolated enum GridStatus: String, Codable, Equatable { case active, complete }

nonisolated enum GridError: Error, Equatable {
    /// The bounded header-reroll budget was exhausted without an all-solvable draw.
    case infeasibleGrid
    /// The submitted player id isn't in the pool.
    case unknownPlayer
    /// The player doesn't satisfy AND(row, col) for that cell.
    case doesNotSatisfy
    /// The cell is already filled.
    case cellFilled
    /// The player was already used in another cell (one player per grid).
    case alreadyUsed
    /// The grid is already complete.
    case gameComplete
    /// The cell address is out of range.
    case invalidCell
}

/// The whole GRID session — a pure value. `rowAxes`/`colAxes` are the 3 headers on
/// each side; `cellFills` records answered cells; `usedPlayerIds` enforces
/// one-player-per-grid; `score` is the running rarity total.
nonisolated struct GridState: Codable, Equatable {
    let definition: GridDefinition
    let pool: [HistoricalPlayerEntity]
    let rowAxes: [GridAxis]        // count == definition.rows (3)
    let colAxes: [GridAxis]        // count == definition.cols (3)
    var cellFills: [GridCell: GridFillResult]
    var usedPlayerIds: Set<String>
    var rng: SeededRNG
    var score: Int
    var status: GridStatus

    func entity(_ id: String) -> HistoricalPlayerEntity? { pool.first { $0.id == id } }

    /// The total number of cells (rows × cols).
    var cellCount: Int { rowAxes.count * colAxes.count }
}

nonisolated enum GridEngine {

    /// Bounded reroll budget for the always-solvable header search (mirrors
    /// `GameFeasibility`'s conservative bounded discipline — terminate + throw
    /// rather than loop).
    static let maxRerollAttempts = 200

    // MARK: - Initialize (always-solvable generation)

    /// Generate a 3×3 whose EVERY cell has ≥ `minCellAnswers` distinct eligible
    /// answers AND whose 9 cells admit a GLOBAL system of 9 DISTINCT representative
    /// players (Hall's condition), because `submitAnswer` enforces one-player-per-grid
    /// — per-cell nonemptiness alone can strand the last cell. Draws row/col headers
    /// from the pool's occurring axes (per the preset's `axisFamilies`), verifies
    /// per-cell solvability THEN a size-9 maximum bipartite matching, and rerolls
    /// headers on any failure up to `maxRerollAttempts`; throws `.infeasibleGrid`
    /// past the budget. Deterministic: same seed ⇒ same headers (sorted matching
    /// iteration, no Set-order dependence).
    static func initialize(definition: GridDefinition,
                           pool: [HistoricalPlayerEntity],
                           seed: UInt64) throws -> GridState {
        // De-dup pool by id (a dup would corrupt eligibility counts & used-set).
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }

        let candidates = candidateAxes(family: definition.axisFamilies, pool: unique)
        guard candidates.count >= definition.rows + definition.cols else {
            throw GridError.infeasibleGrid
        }

        var rng = SeededRNG(seed: seed)
        var attempt = 0
        while attempt < maxRerollAttempts {
            attempt += 1
            let shuffled = candidates.shuffled(using: &rng)
            let rowAxes = Array(shuffled.prefix(definition.rows))
            let colAxes = Array(shuffled.dropFirst(definition.rows).prefix(definition.cols))
            guard colAxes.count == definition.cols else { continue }
            if allCellsSolvable(rowAxes: rowAxes, colAxes: colAxes,
                                pool: unique, minAnswers: definition.minCellAnswers),
               gridHasDistinctSolution(rowAxes: rowAxes, colAxes: colAxes, pool: unique) {
                return GridState(definition: definition, pool: unique,
                                 rowAxes: rowAxes, colAxes: colAxes,
                                 cellFills: [:], usedPlayerIds: [],
                                 rng: rng, score: 0, status: .active)
            }
        }
        throw GridError.infeasibleGrid
    }

    /// Every one of the rows×cols cells has ≥ `minAnswers` distinct answers.
    static func allCellsSolvable(rowAxes: [GridAxis], colAxes: [GridAxis],
                                 pool: [HistoricalPlayerEntity],
                                 minAnswers: Int) -> Bool {
        for r in rowAxes {
            for c in colAxes {
                if GridRarityScorer.eligibleCount(row: r, col: c, pool: pool) < minAnswers {
                    return false
                }
            }
        }
        return true
    }

    /// True iff the rows×cols cells admit a SYSTEM OF DISTINCT REPRESENTATIVES: a
    /// maximum bipartite matching (cells ↔ players, an edge iff the player satisfies
    /// that cell) of size == cellCount. Because `submitAnswer` bans reusing a player
    /// across cells, this global check — not just per-cell nonemptiness — is what
    /// guarantees the grid can actually be completed (Hall's theorem).
    ///
    /// Deterministic: cells are matched in a fixed 0..<count order and each cell's
    /// eligible player ids are iterated in SORTED order (no Set-iteration
    /// dependence), so the same headers/pool always yield the same accept/reject.
    static func gridHasDistinctSolution(rowAxes: [GridAxis], colAxes: [GridAxis],
                                        pool: [HistoricalPlayerEntity]) -> Bool {
        let cellCount = rowAxes.count * colAxes.count
        guard cellCount > 0 else { return true }

        // cell index → sorted eligible player ids.
        var cellEligibles: [[String]] = []
        cellEligibles.reserveCapacity(cellCount)
        for r in rowAxes {
            for c in colAxes {
                let ids = pool.filter { $0.satisfies(row: r, col: c) }
                    .map { $0.id }
                    .sorted()
                cellEligibles.append(ids)
            }
        }

        // Kuhn's algorithm (DFS augmenting paths): match each cell (left) to a
        // distinct player (right). `playerToCell[playerId]` = the cell currently
        // holding that player.
        var playerToCell: [String: Int] = [:]
        var matchedCells = 0

        func augment(_ cell: Int, _ visited: inout Set<String>) -> Bool {
            for pid in cellEligibles[cell] where visited.insert(pid).inserted {
                // Free player, or the cell currently holding it can be re-routed.
                if playerToCell[pid] == nil || augment(playerToCell[pid]!, &visited) {
                    playerToCell[pid] = cell
                    return true
                }
            }
            return false
        }

        for cell in 0..<cellCount {
            var visited = Set<String>()
            if augment(cell, &visited) { matchedCells += 1 }
        }
        return matchedCells == cellCount
    }

    /// The distinct concrete axes that OCCUR in the pool for the enabled families,
    /// sorted by `sortKey` so the candidate ordering is reproducible before the
    /// seeded shuffle.
    static func candidateAxes(family families: [GridAxisFamily],
                              pool: [HistoricalPlayerEntity]) -> [GridAxis] {
        var axes = Set<GridAxis>()
        for fam in families {
            switch fam {
            case .franchise:
                for e in pool { for tri in e.franchises { axes.insert(.franchise(tri)) } }
            case .decade:
                for e in pool { for d in e.decades { axes.insert(.decade(d)) } }
            case .positionFamily:
                for e in pool { for f in e.families { axes.insert(.positionFamily(f)) } }
            case .award:
                // Broad awards only if some pool player actually holds them.
                if pool.contains(where: { $0.careerRings >= 1 })    { axes.insert(.award("ring")) }
                if pool.contains(where: { $0.careerAllNba >= 1 })   { axes.insert(.award("allNba")) }
                if pool.contains(where: { $0.careerAllStar >= 1 })  { axes.insert(.award("allStar")) }
            }
        }
        return axes.sorted { $0.sortKey < $1.sortKey }
    }

    // MARK: - Submit an answer

    /// Fill a cell with a distinct player. Validates: cell in range, cell empty,
    /// player known, player not already used, and player satisfies AND(row, col).
    /// Scores eligibility-rarity, marks the cell, completes when all cells filled.
    static func submitAnswer(_ state: GridState, cell: GridCell,
                             playerId: String) throws -> GridState {
        guard state.status == .active else { throw GridError.gameComplete }
        guard cell.row >= 0, cell.row < state.rowAxes.count,
              cell.col >= 0, cell.col < state.colAxes.count else { throw GridError.invalidCell }
        guard state.cellFills[cell] == nil else { throw GridError.cellFilled }
        guard let entity = state.entity(playerId) else { throw GridError.unknownPlayer }
        guard !state.usedPlayerIds.contains(playerId) else { throw GridError.alreadyUsed }

        let row = state.rowAxes[cell.row]
        let col = state.colAxes[cell.col]
        guard entity.satisfies(row: row, col: col) else { throw GridError.doesNotSatisfy }

        let count = GridRarityScorer.eligibleCount(row: row, col: col, pool: state.pool)
        let points = GridRarityScorer.rarity(count: count, scaling: state.definition.rarityScaling)

        var next = state
        next.cellFills[cell] = GridFillResult(playerId: playerId, playerName: entity.name, points: points)
        next.usedPlayerIds.insert(playerId)
        next.score += points
        if next.cellFills.count == next.cellCount { next.status = .complete }
        return next
    }
}
