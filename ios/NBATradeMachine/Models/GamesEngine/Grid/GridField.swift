import Foundation

/// The SET-MEMBERSHIP axis predicate for GRID, evaluated against a distinct
/// `HistoricalPlayerEntity`. This is a GENUINELY-new small evaluator (NOT a reuse
/// of `GameField`/`GameConstraintEvaluator`): the roster evaluator's model is
/// SCALAR (one `position`, one `decadeStartYear`, one award count per entity),
/// but a distinct player belongs to MANY franchises/decades/families over a
/// career — a one-to-many membership the scalar model can't express. Keeping the
/// grid's legality self-contained here avoids distorting the roster evaluator.
///
/// `GridAxis` is the header on a row or column; a cell = AND(rowAxis, colAxis),
/// and a player satisfies the cell iff they satisfy BOTH axes.
nonisolated enum GridAxis: Codable, Equatable, Hashable {
    /// Played an eligible season for this franchise (team tricode, e.g. "LAL").
    case franchise(String)
    /// Played an eligible season in this decade (start year 1990/2000/2010/2020).
    case decade(Int)
    /// Belongs to this position family ("GUARD"/"WING"/"BIG").
    case positionFamily(String)
    /// Won at least one of a broad award. `key` ∈ {"ring","allNba","allStar"}
    /// (Sol's first-ship award axes; MVP & stat-thresholds DEFERRED).
    case award(String)

    /// A short human label for the header cell.
    var displayLabel: String {
        switch self {
        case .franchise(let tri):     return tri
        case .decade(let start):      return "\(start)s"
        case .positionFamily(let f):  return f.capitalized
        case .award(let key):
            switch key {
            case "ring":    return "Champion"
            case "allNba":  return "All-NBA"
            case "allStar": return "All-Star"
            default:        return key
            }
        }
    }

    /// A stable key used for RNG-reproducible ordering and de-dup within an axis
    /// family (so the same seed always draws the same header).
    var sortKey: String {
        switch self {
        case .franchise(let tri):     return "franchise:\(tri)"
        case .decade(let start):      return "decade:\(start)"
        case .positionFamily(let f):  return "family:\(f)"
        case .award(let key):         return "award:\(key)"
        }
    }
}

nonisolated extension HistoricalPlayerEntity {
    /// SET-membership test: does this distinct player satisfy the axis?
    func satisfies(_ axis: GridAxis) -> Bool {
        switch axis {
        case .franchise(let tri):     return franchises.contains(tri)
        case .decade(let start):      return decades.contains(start)
        case .positionFamily(let f):  return families.contains(f)
        case .award(let key):
            switch key {
            case "ring":    return careerRings >= 1
            case "allNba":  return careerAllNba >= 1
            case "allStar": return careerAllStar >= 1
            default:        return false   // unknown award key never satisfies
            }
        }
    }

    /// A cell = AND(row, col): the player must satisfy BOTH axes.
    func satisfies(row: GridAxis, col: GridAxis) -> Bool {
        satisfies(row) && satisfies(col)
    }
}
