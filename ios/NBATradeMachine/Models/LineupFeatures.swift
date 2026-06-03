import Foundation

/// Per-player lineup-feature record, written to `players/{slug}.lineupFeatures`
/// by scripts/upload_lineup_features.py. Every field is optional so a player
/// without a current-season feature record (or an older doc) decodes cleanly to
/// nil and the labeling engine abstains rather than crashing.
///
/// The field names mirror the Python feature record exactly — they are the keys
/// the labeling engine looks up (via `LeagueNorms`) when ranking a player
/// against the league.
struct LineupFeatures: Codable, Equatable, Hashable {
    // Shot-location z-scores.
    let z_ra: Double?
    let z_paint: Double?
    let z_mid: Double?
    let z_lc3: Double?
    let z_rc3: Double?
    let z_atb3: Double?
    let z_corner3: Double?

    // Volume / efficiency.
    let fga_total: Double?
    let ts: Double?
    let efg: Double?
    let three_par: Double?
    let fg3_pct: Double?
    let sq: Double?

    // Creation / load.
    let load: Double?
    let box_creation: Double?
    let passer_rtg: Double?
    let usg: Double?
    let ctov_pct: Double?

    // Rebounding.
    let orb_pct: Double?
    let drb_pct: Double?
    let reb_pct: Double?

    // Defense / versatility.
    let versatility: Double?
    let blk_pct: Double?
    let stl_pct: Double?
    let rpf: Double?
    let portability: Double?

    // Real tracking defense / pace (Phase-1 de-proxy). Percentile features
    // unless noted; pnr_roll_def_pctl is read RAW as an already-0..1 percentile.
    let pace: Double?
    let deflections_per36: Double?
    let contested_per36: Double?
    let rim_dfga_per36: Double?
    let rim_opp_fg_pct: Double?
    let rim_def_delta: Double?
    let perim_opp_fg3_pct: Double?
    let perim_def_delta: Double?
    let pnr_roll_def_pctl: Double?

    // Free-throw / turnover.
    let ftr: Double?
    let ft_pct: Double?
    let tov_pct: Double?

    // Physicals.
    let height_in: Double?
    let weight_lb: Double?
    let wingspan_in: Double?

    // Role / age.
    let primary_pos: String?
    let position: String?
    let age: Double?

    /// Raw feature lookup by name — the engine reads features by string key
    /// (mirroring the Python `feat(player, name)`), so a single dispatch keeps
    /// it in lock-step with the norms map. Returns nil for any unknown or
    /// missing feature.
    func value(_ name: String) -> Double? {
        switch name {
        case "z_ra": return z_ra
        case "z_paint": return z_paint
        case "z_mid": return z_mid
        case "z_lc3": return z_lc3
        case "z_rc3": return z_rc3
        case "z_atb3": return z_atb3
        case "z_corner3": return z_corner3
        case "fga_total": return fga_total
        case "ts": return ts
        case "efg": return efg
        case "three_par": return three_par
        case "fg3_pct": return fg3_pct
        case "sq": return sq
        case "load": return load
        case "box_creation": return box_creation
        case "passer_rtg": return passer_rtg
        case "usg": return usg
        case "ctov_pct": return ctov_pct
        case "orb_pct": return orb_pct
        case "drb_pct": return drb_pct
        case "reb_pct": return reb_pct
        case "versatility": return versatility
        case "blk_pct": return blk_pct
        case "stl_pct": return stl_pct
        case "rpf": return rpf
        case "portability": return portability
        case "pace": return pace
        case "deflections_per36": return deflections_per36
        case "contested_per36": return contested_per36
        case "rim_dfga_per36": return rim_dfga_per36
        case "rim_opp_fg_pct": return rim_opp_fg_pct
        case "rim_def_delta": return rim_def_delta
        case "perim_opp_fg3_pct": return perim_opp_fg3_pct
        case "perim_def_delta": return perim_def_delta
        case "pnr_roll_def_pctl": return pnr_roll_def_pctl
        case "ftr": return ftr
        case "ft_pct": return ft_pct
        case "tov_pct": return tov_pct
        case "height_in": return height_in
        case "weight_lb": return weight_lb
        case "wingspan_in": return wingspan_in
        case "age": return age
        default: return nil
        }
    }

    /// Position string used by archetype role tests: primary_pos, falling back
    /// to position, uppercased (mirrors archetypes._pos).
    var pos: String {
        (primary_pos ?? position ?? "").uppercased()
    }
}
