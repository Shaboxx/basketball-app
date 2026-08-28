import Foundation

/// The custom-game creator's BOUNDED choice menus (spec §27 progressive
/// disclosure). Everything here is DATA, not free-form authoring: the wizard only
/// recombines existing engine knobs, so every draft it can produce is a legal
/// Definition the shipped engines already run. Free-form constraint authoring is
/// deliberately NOT offered — it would emit illegal/degenerate games the
/// validator would just reject (risk §134).
nonisolated enum CreatorOptions {

    // MARK: - Engine family

    /// The engine families a user can author. Maps 1:1 to a `GameLaunch` case.
    nonisolated enum EngineFamily: String, Codable, Equatable, CaseIterable, Identifiable {
        case roster        // ROSTER_CONSTRUCTION
        case classification
        case compare
        case bracket

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .roster:         return "Roster Draft"
            case .classification: return "Ranking / Tiers"
            case .compare:        return "Higher or Lower"
            case .bracket:        return "Bracket"
            }
        }
    }

    // MARK: - Roster shapes

    /// Bounded roster shapes. `.positionless(n)` is capped at
    /// `maxPositionlessSlots` so the creator can't drive `GameFeasibility` toward
    /// its known large-roster budget limit (risk §132).
    nonisolated enum RosterShape: Codable, Equatable, Identifiable, Hashable {
        case startingFive
        case flexFive
        case positionless(Int)

        var id: String {
            switch self {
            case .startingFive:      return "startingFive"
            case .flexFive:          return "flexFive"
            case .positionless(let n): return "positionless-\(n)"
            }
        }

        var displayName: String {
            switch self {
            case .startingFive:        return "Starting Five (PG–C)"
            case .flexFive:            return "Flex Five (G/G/W/W/B)"
            case .positionless(let n): return "\(n) Any-Position"
            }
        }

        var config: RosterConfig {
            switch self {
            case .startingFive:        return .startingFive
            case .flexFive:            return .flexFive
            case .positionless(let n): return .positionless(n)
            }
        }
    }

    /// Cap on positionless roster size (risk §132: keep rosters small enough that
    /// `GameFeasibility.canComplete` stays exact, well under its node budget).
    static let maxPositionlessSlots = 8

    static let rosterShapes: [RosterShape] = [
        .startingFive, .flexFive,
        .positionless(3), .positionless(5), .positionless(8),
    ]

    // MARK: - Selection & scoring

    static let selectionMethods: [SelectionMethod] = [.freePick, .snake]

    /// Roster scoring choices the creator offers (a subset — no per-slot
    /// `slotMetric` authoring, which the Create-A-Player preset already ships).
    static let rosterScoring: [ScoringMethod] = [.teamRating, .none]

    // MARK: - Economy presets

    /// Bounded economy presets (nil = no budget). Each is a legal `EconomyConfig`.
    nonisolated enum EconomyPreset: String, Codable, Equatable, CaseIterable, Identifiable {
        case noBudget
        case salaryCap120M
        case tierBudget20

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .noBudget:      return "No Budget"
            case .salaryCap120M: return "$120M Salary Cap"
            case .tierBudget20:  return "$20 Tier Budget"
            }
        }

        var config: EconomyConfig? {
            switch self {
            case .noBudget:      return nil
            case .salaryCap120M: return EconomyConfig(pricingMethod: .databaseValue,
                                                      startingBudget: 120_000_000)
            case .tierBudget20:  return EconomyConfig(pricingMethod: .tierPrice,
                                                      startingBudget: 20)
            }
        }
    }

    // MARK: - Constraint palette (bounded)

    /// The bounded pool-filter palette. Each maps to a legal `GameConstraint` (or
    /// `RosterConstraint`). No free-form authoring — only these named filters.
    nonisolated enum PoolFilter: Codable, Equatable, Identifiable, Hashable {
        case minRating(Double)       // rating >= threshold
        case position(String)        // position == code
        case uniqueTeams             // uniqueBy(.team) — a ROSTER constraint

        var id: String {
            switch self {
            case .minRating(let r): return "minRating-\(r)"
            case .position(let p):  return "position-\(p)"
            case .uniqueTeams:      return "uniqueTeams"
            }
        }

        var displayName: String {
            switch self {
            case .minRating(let r): return String(format: "Rating ≥ %.0f", r)
            case .position(let p):  return "Position: \(p)"
            case .uniqueTeams:      return "One player per team"
            }
        }

        /// The entity-scope constraint (pool filter), or nil for a roster-scope one.
        var entityConstraint: GameConstraint? {
            switch self {
            case .minRating(let r):
                return .field(FieldConstraint(field: .rating, op: .greaterOrEqual,
                                              value: .number(r)))
            case .position(let p):
                return .field(FieldConstraint(field: .position, op: .equal,
                                              value: .string(p)))
            case .uniqueTeams:
                return nil
            }
        }

        /// The roster-scope constraint, or nil for an entity-scope one.
        var rosterConstraint: RosterConstraint? {
            switch self {
            case .uniqueTeams: return .uniqueBy(.team)
            default:           return nil
            }
        }
    }

    /// The palette offered in the wizard.
    static let poolFilters: [PoolFilter] = [
        .uniqueTeams,
        .minRating(0), .minRating(3), .minRating(5),
        .position("PG"), .position("SG"), .position("SF"), .position("PF"), .position("C"),
    ]

    // MARK: - Bracket field sizes

    static let bracketFieldSizes: [Int] = [4, 8, 16]

    static let bracketScoring: [BracketScoring] = [.none, .modelAgreement]

    // MARK: - Compare metrics / classification modes

    static let compareMetrics: [CompareMetric] = [.overall, .offense, .defense, .salary, .minutes]
    static let compareDirections: [CompareDirection] = [.higher, .lower]

    static let classificationModes: [ClassificationMode] = [.totalOrder, .tiers, .uniqueLabels]
}
