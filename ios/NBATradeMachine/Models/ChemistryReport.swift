import Foundation

/// Forward-compatibility type for the post-trade chemistry projection
/// (Phase 7f, not yet computed). Carries a single composite score plus
/// per-pair compatibility entries so the Trade Confirmation view can render
/// a real card the moment the calculation lands.
///
/// While `chemistry == nil` the UI shows a "Coming soon" placeholder tile.
/// The shape is intentionally permissive (all optional) so an early shim
/// emitting only `score` is enough to flip the tile from placeholder to live.
struct ChemistryReport: Codable, Equatable, Hashable {
    /// Composite chemistry score for the resulting roster (z-scale, higher =
    /// better fit). Sign indicates "better than the roster average pairing"
    /// when positive.
    let score: Double?

    /// Schema version of the chemistry block; bumped when the contract changes.
    let version: String?

    /// Per-pair compatibility entries. `playerSlugs` must contain exactly
    /// two slugs; `delta` is the pair's contribution to `score`.
    let pairs: [PairEntry]?

    /// Optional human-readable summary line for the rollup footer.
    let summary: String?

    struct PairEntry: Codable, Equatable, Hashable {
        let playerSlugs: [String]?
        let delta: Double?
        let note: String?
    }
}

/// Forward-compatibility type for the lineup's ideal-peak window projection
/// (Phase 7f, not yet computed). Identifies the season range where the new
/// roster's combined latent value is forecast to peak.
///
/// While `peakTimeline == nil` the view shows a "Coming soon" placeholder.
struct PeakTimelineForecast: Codable, Equatable, Hashable {
    /// First peak-window season (e.g. "2026-27"). Inclusive.
    let peakStartSeason: String?

    /// Final peak-window season (e.g. "2028-29"). Inclusive.
    let peakEndSeason: String?

    /// Forecast roster-wide composite theta at the peak window center.
    let peakComposite: Double?

    /// Confidence band on `peakComposite` (1 SE).
    let peakCompositeSE: Double?

    /// Optional summary line ("Peaks 2027-28 (3 seasons)").
    let summary: String?

    let version: String?
}
