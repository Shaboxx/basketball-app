import Foundation

/// A small declarative pool prefilter applied by `HistoricalPoolBuilder` BEFORE
/// the (unchanged) `GameDefinition.entityConstraints` run. It cheaply slices the
/// 14569-record dataset down to a decade / award-gated subset so a single-decade
/// game never builds 14569 `GameEntityRecord`s.
///
/// Enforcement split (deliberate): the `requireEligible` gate is AUTHORITATIVE
/// and lives ONLY here — there is no `eligible` `GameField`, so the engine's
/// `entityConstraints` cannot re-express it; every historical pool MUST flow
/// through this prefilter (the sole historical pool path does). For all OTHER
/// facets (decade / award / rating), the prefilter is a non-narrowing performance
/// slice and the definition-level `entityConstraints` are the authoritative gate
/// that `initialize` re-applies — so the prefilter here must never be NARROWER
/// than the constraints on those facets, or it would hide an admissible entity.
/// (Any future pool builder that bypasses this prefilter must re-apply the
/// eligibility gate itself.)
///
/// `nonisolated` so it can be constructed / applied off the main actor.
nonisolated struct HistoricalFilter: Codable, Equatable {
    /// Restrict to one decade (1990/2000/2010/2020). nil = all decades.
    let decadeStartYear: Int?
    /// Drop rows with `eligible == false` (the dataset's minGp/minMpg gate).
    let requireEligible: Bool
    /// Optional overall-rating floor (cheap pre-slice for thin all-time pools).
    let minRating: Double?
    /// Optional award minimums, keyed by a career field name matching the
    /// `GameField` raw value: "careerRings", "careerMvp", "careerAllNba",
    /// "careerAllStar", "careerAllDefense", "careerFinalsMvp". Each value is an
    /// inclusive minimum count. Absent/nil-count records fail the gate.
    let awardMin: [String: Int]?

    init(decadeStartYear: Int? = nil, requireEligible: Bool = true,
         minRating: Double? = nil, awardMin: [String: Int]? = nil) {
        self.decadeStartYear = decadeStartYear
        self.requireEligible = requireEligible
        self.minRating = minRating
        self.awardMin = awardMin
    }

    /// The full-league, all-decade, eligible-only pool (used by all-time cards).
    static let allEligible = HistoricalFilter()
}
