import Foundation

/// Comparison operators (spec §6). String ops: equal/notEqual/isIn/notIn.
/// Numeric ops: all of them; `between` is inclusive on both ends.
nonisolated enum ConstraintOperator: String, Codable, Equatable {
    case equal, notEqual, isIn, notIn
    case greaterThan, greaterOrEqual, lessThan, lessOrEqual, between
}

/// The right-hand side of a field comparison.
nonisolated enum ConstraintValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case strings([String])
    case range(min: Double, max: Double)
}

/// One field comparison against a single entity.
nonisolated struct FieldConstraint: Codable, Equatable {
    let field: GameField
    let op: ConstraintOperator
    let value: ConstraintValue
}

/// Boolean-composable entity-scope constraint (spec §6 composition).
nonisolated indirect enum GameConstraint: Codable, Equatable {
    case field(FieldConstraint)
    case and([GameConstraint])
    case or([GameConstraint])
    case not(GameConstraint)
}

/// Roster-scope aggregate constraints (spec §6). All gate every pick except
/// `minCountWhere`, which is a completion requirement (you can't have "at least
/// one center" after pick 1 of 5).
nonisolated enum RosterConstraint: Codable, Equatable {
    case uniqueBy(GameField)
    case maxCountWhere(GameConstraint, Int)
    case minCountWhere(GameConstraint, Int)
    case totalAtMost(GameField, Double)
}

nonisolated enum GameConstraintEvaluator {

    static func satisfies(_ entity: GameEntityRecord, _ constraint: GameConstraint) -> Bool {
        switch constraint {
        case .field(let f): return compare(entity.value(for: f.field), f.op, f.value)
        case .and(let cs):  return cs.allSatisfy { satisfies(entity, $0) }
        case .or(let cs):   return cs.contains { satisfies(entity, $0) }
        case .not(let c):   return !satisfies(entity, c)
        }
    }

    /// May `candidate` join `roster` under every pick-gating constraint?
    static func allowsPick(roster: [GameEntityRecord], candidate: GameEntityRecord,
                           constraints: [RosterConstraint]) -> Bool {
        constraints.allSatisfy { holds(roster + [candidate], $0, atCompletion: false) }
    }

    /// Does a finished roster satisfy every constraint, including `minCountWhere`?
    static func satisfiesCompleted(_ roster: [GameEntityRecord],
                                   constraints: [RosterConstraint]) -> Bool {
        constraints.allSatisfy { holds(roster, $0, atCompletion: true) }
    }

    private static func holds(_ roster: [GameEntityRecord], _ c: RosterConstraint,
                              atCompletion: Bool) -> Bool {
        switch c {
        case .uniqueBy(let field):
            // Entities missing the field are exempt (nil never collides with nil).
            let keys = roster.compactMap { $0.value(for: field).map(key) }
            return keys.count == Set(keys).count
        case .maxCountWhere(let cond, let maxCount):
            return roster.filter { satisfies($0, cond) }.count <= maxCount
        case .minCountWhere(let cond, let minCount):
            return !atCompletion || roster.filter { satisfies($0, cond) }.count >= minCount
        case .totalAtMost(let field, let cap):
            let total = roster.compactMap { e -> Double? in
                if case .number(let n)? = e.value(for: field) { return n }
                return nil
            }.reduce(0, +)
            return total <= cap
        }
    }

    /// Missing data or a type-mismatched constraint never satisfies — including
    /// `notEqual`/`notIn` (a nil field fails those too, SQL-style). The `.not`
    /// combinator is classical negation and therefore DOES flip that `false` to
    /// `true`; the two spellings are not interchangeable on missing data.
    private static func compare(_ lhs: GameFieldValue?, _ op: ConstraintOperator,
                                _ rhs: ConstraintValue) -> Bool {
        guard let lhs else { return false }
        switch (lhs, op, rhs) {
        case let (.string(s), .equal, .string(v)):          return s == v
        case let (.string(s), .notEqual, .string(v)):       return s != v
        case let (.string(s), .isIn, .strings(vs)):         return vs.contains(s)
        case let (.string(s), .notIn, .strings(vs)):        return !vs.contains(s)
        case let (.number(n), .equal, .number(v)):          return n == v
        case let (.number(n), .notEqual, .number(v)):       return n != v
        case let (.number(n), .greaterThan, .number(v)):    return n > v
        case let (.number(n), .greaterOrEqual, .number(v)): return n >= v
        case let (.number(n), .lessThan, .number(v)):       return n < v
        case let (.number(n), .lessOrEqual, .number(v)):    return n <= v
        case let (.number(n), .between, .range(lo, hi)):    return n >= lo && n <= hi
        default:                                            return false
        }
    }

    private static func key(_ v: GameFieldValue) -> String {
        switch v {
        case .string(let s): return "s:\(s)"
        case .number(let n): return "n:\(n)"
        }
    }
}
