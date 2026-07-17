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
    let corner3_fg_pct: Double?
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

    // Bridge creation-share (nba_api USG breakdown, 2025-26).
    let creation_share: Double?
    let creation_share_src: String?
    let creation_share_season: String?
    let creation_volume: Double?

    init(
        z_ra: Double?, z_paint: Double?, z_mid: Double?, z_lc3: Double?, z_rc3: Double?,
        z_atb3: Double?, z_corner3: Double?, fga_total: Double?, ts: Double?, efg: Double?,
        three_par: Double?, fg3_pct: Double?, corner3_fg_pct: Double? = nil, sq: Double?, load: Double?, box_creation: Double?,
        passer_rtg: Double?, usg: Double?, ctov_pct: Double?, orb_pct: Double?, drb_pct: Double?,
        reb_pct: Double?, versatility: Double?, blk_pct: Double?, stl_pct: Double?, rpf: Double?,
        portability: Double?, pace: Double?, deflections_per36: Double?, contested_per36: Double?,
        rim_dfga_per36: Double?, rim_opp_fg_pct: Double?, rim_def_delta: Double?,
        perim_opp_fg3_pct: Double?, perim_def_delta: Double?, pnr_roll_def_pctl: Double?,
        ftr: Double?, ft_pct: Double?, tov_pct: Double?, height_in: Double?, weight_lb: Double?,
        wingspan_in: Double?, primary_pos: String?, position: String?, age: Double?,
        creation_share: Double? = nil, creation_share_src: String? = nil,
        creation_share_season: String? = nil,
        creation_volume: Double? = nil
    ) {
        self.z_ra = z_ra; self.z_paint = z_paint; self.z_mid = z_mid
        self.z_lc3 = z_lc3; self.z_rc3 = z_rc3; self.z_atb3 = z_atb3
        self.z_corner3 = z_corner3; self.fga_total = fga_total; self.ts = ts; self.efg = efg
        self.three_par = three_par; self.fg3_pct = fg3_pct; self.corner3_fg_pct = corner3_fg_pct
        self.sq = sq; self.load = load
        self.box_creation = box_creation; self.passer_rtg = passer_rtg; self.usg = usg
        self.ctov_pct = ctov_pct; self.orb_pct = orb_pct; self.drb_pct = drb_pct; self.reb_pct = reb_pct
        self.versatility = versatility; self.blk_pct = blk_pct; self.stl_pct = stl_pct
        self.rpf = rpf; self.portability = portability; self.pace = pace
        self.deflections_per36 = deflections_per36; self.contested_per36 = contested_per36
        self.rim_dfga_per36 = rim_dfga_per36; self.rim_opp_fg_pct = rim_opp_fg_pct
        self.rim_def_delta = rim_def_delta; self.perim_opp_fg3_pct = perim_opp_fg3_pct
        self.perim_def_delta = perim_def_delta; self.pnr_roll_def_pctl = pnr_roll_def_pctl
        self.ftr = ftr; self.ft_pct = ft_pct; self.tov_pct = tov_pct; self.height_in = height_in
        self.weight_lb = weight_lb; self.wingspan_in = wingspan_in; self.primary_pos = primary_pos
        self.position = position; self.age = age; self.creation_share = creation_share
        self.creation_share_src = creation_share_src; self.creation_share_season = creation_share_season
        self.creation_volume = creation_volume
    }

    /// Raw feature lookup by name — the engine reads features by string key
    /// (mirroring the Python `feat(player, name)`), so a single dispatch keeps
    /// it in lock-step with the norms map. Returns nil for any unknown or
    /// missing feature.
    nonisolated func value(_ name: String) -> Double? {
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
        case "corner3_fg_pct": return corner3_fg_pct
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
        case "creation_share": return creation_share
        case "creation_volume": return creation_volume
        default: return nil
        }
    }

    /// Position string used by archetype role tests: primary_pos, falling back
    /// to position, uppercased (mirrors archetypes._pos).
    nonisolated var pos: String {
        (primary_pos ?? position ?? "").uppercased()
    }
}
