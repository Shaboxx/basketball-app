import Foundation

/// The DISTINCT-player frozen entity — one per `nbaPlayerId`, collapsed across all
/// that player's eligible season records. This is the shared answer-space GRID and
/// CONNECTION resolve typed names against; it is kept SEPARATE from the
/// season-level `GameEntityRecord` (which the roster/compare/guess games use),
/// because GRID's axes are one-to-many SET memberships (a player belongs to many
/// franchises/decades/families over a career) that the scalar `GameEntityRecord`
/// model can't express.
///
/// `id` is `String(nbaPlayerId)` so it joins cleanly to `teammate-graph.json`
/// (whose node keys are the same numeric nba ids as strings).
///
/// All members are Sendable value types → the whole struct is `Sendable`, so a
/// `[HistoricalPlayerEntity]` can be returned from the store's `Task.detached`
/// collapse back to the main actor without a data-race diagnostic under Swift 6.
nonisolated struct HistoricalPlayerEntity: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// `String(nbaPlayerId)` — the join key to the teammate graph.
    let id: String
    /// Most-recent (highest season) display name for the player.
    let name: String
    /// Optional bridge back to the live app `Player` doc (headshots / UI).
    let appSlug: String?
    /// Union of team tricodes the player logged an eligible season with.
    let franchises: Set<String>
    /// Union of decade start years (1990/2000/2010/2020) the player played in.
    let decades: Set<Int>
    /// Union of position families (GUARD/WING/BIG) across the player's seasons.
    let families: Set<String>
    /// Best (max) career accolade counts seen across the player's records.
    let careerRings: Int
    let careerMvp: Int
    let careerAllNba: Int
    let careerAllStar: Int
    let careerAllDefense: Int
    /// The best (max) overall rating across the player's eligible seasons.
    let bestRating: Double

    init(id: String, name: String, appSlug: String?,
         franchises: Set<String>, decades: Set<Int>, families: Set<String>,
         careerRings: Int, careerMvp: Int, careerAllNba: Int,
         careerAllStar: Int, careerAllDefense: Int, bestRating: Double) {
        self.id = id
        self.name = name
        self.appSlug = appSlug
        self.franchises = franchises
        self.decades = decades
        self.families = families
        self.careerRings = careerRings
        self.careerMvp = careerMvp
        self.careerAllNba = careerAllNba
        self.careerAllStar = careerAllStar
        self.careerAllDefense = careerAllDefense
        self.bestRating = bestRating
    }

    // MARK: - Canonical (sorted) Codable
    //
    // The three Set members encode as SORTED arrays and decode arrays back into
    // Sets, so serializing the same entity twice is BYTE-IDENTICAL. Swift's
    // synthesized Set encoding is hash-order (non-canonical) — a latent
    // byte-identical-replay hazard once Phase-7 state is persisted/synced. Equatable
    // & Hashable stay order-independent (Set semantics unchanged).

    private enum CodingKeys: String, CodingKey {
        case id, name, appSlug, franchises, decades, families,
             careerRings, careerMvp, careerAllNba, careerAllStar,
             careerAllDefense, bestRating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        appSlug = try c.decodeIfPresent(String.self, forKey: .appSlug)
        franchises = Set(try c.decode([String].self, forKey: .franchises))
        decades = Set(try c.decode([Int].self, forKey: .decades))
        families = Set(try c.decode([String].self, forKey: .families))
        careerRings = try c.decode(Int.self, forKey: .careerRings)
        careerMvp = try c.decode(Int.self, forKey: .careerMvp)
        careerAllNba = try c.decode(Int.self, forKey: .careerAllNba)
        careerAllStar = try c.decode(Int.self, forKey: .careerAllStar)
        careerAllDefense = try c.decode(Int.self, forKey: .careerAllDefense)
        bestRating = try c.decode(Double.self, forKey: .bestRating)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(appSlug, forKey: .appSlug)
        try c.encode(franchises.sorted(), forKey: .franchises)
        try c.encode(decades.sorted(), forKey: .decades)
        try c.encode(families.sorted(), forKey: .families)
        try c.encode(careerRings, forKey: .careerRings)
        try c.encode(careerMvp, forKey: .careerMvp)
        try c.encode(careerAllNba, forKey: .careerAllNba)
        try c.encode(careerAllStar, forKey: .careerAllStar)
        try c.encode(careerAllDefense, forKey: .careerAllDefense)
        try c.encode(bestRating, forKey: .bestRating)
    }
}
