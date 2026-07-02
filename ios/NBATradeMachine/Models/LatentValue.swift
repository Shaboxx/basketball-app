import Foundation

/// Phase 7 v2 (Rev 2) latent player value: the fused CraftedPM + EPM latent
/// impact (theta-hat) in points / 100 possessions, plus per-season standardized
/// (z) variants, multi-season projection, and trajectory-aging diagnostics.
///
/// Written to `players/{slug}.latentValue` by scripts/upload_latent_value.py
/// (Tier A) and the Tier-B branch of scripts/compute_latent_value.py. All
/// fields are optional so a Tier-A doc (weights + priorWeight, no projection)
/// and a Tier-B doc (projection + z + trajectory drift) both decode cleanly.
struct LatentValue: Codable, Equatable, Hashable {
    // Identity / metadata
    let version: String?
    let modelVersion: String?
    let agingAlphaFit: Double?

    // Raw-scale (points / 100) fused theta and per-channel split.
    let theta: Double?
    let thetaOff: Double?
    let thetaDef: Double?
    let se: Double?
    let reliability: Double?

    // Per-season standardized (z) variants — Rev 2 §6 addition.
    let thetaZ: Double?
    let thetaZOff: Double?
    let thetaZDef: Double?
    let seZ: Double?

    // Per-season standardization constants per channel — supports
    // inverse standardization (z -> raw) for downstream consumers.
    let seasonConstants: SeasonConstants?

    // Tier A only.
    let weights: Weights?
    let priorWeight: Int?

    // Tier B only.
    let projection: [Projection]?
    let thetaBySeason: [SeasonPoint]?

    // Trajectory-aging diagnostics — Phase 7 v2 §4.8 (Rev 2). Fused-total
    // basis: one drift on the OFF+DEF smoothed path (the per-channel
    // drift_z_off/def keys were removed from the artifact 2026-07-02).
    let driftZ: Double?
    let trajectoryMaxZ: Double?

    /// Crafted vs. EPM blend weights (Tier A fusion). Sum to ~1.
    struct Weights: Codable, Equatable, Hashable {
        let crafted: Double?
        let epm: Double?
    }

    /// One projected future season (Tier B): theta with growing uncertainty,
    /// reported in both raw (points / 100) and per-season-standardized (z).
    struct Projection: Codable, Equatable, Hashable {
        let season: String?
        let theta: Double?
        let se: Double?
        let thetaZ: Double?
        let seZ: Double?

        enum CodingKeys: String, CodingKey {
            case season, theta, se
            case thetaZ = "theta_z"
            case seZ = "se_z"
        }
    }

    /// One in-sample smoothed season (Tier B): the full per-season smoothed
    /// posterior used by Phase 7b training (historical fair-salary cap%) and
    /// Phase 7d multi-year asset NPV.
    struct SeasonPoint: Codable, Equatable, Hashable {
        let season: String?
        let theta: Double?
        let se: Double?
    }

    /// Per-channel, per-season standardization constants (mu, sd) for both the
    /// CraftedPM (`muC`/`sdC`) and EPM (`muE`/`sdE`) bases. Picks the basis
    /// downstream wants for inverse z standardization.
    struct SeasonConstants: Codable, Equatable, Hashable {
        let off: ChannelConstants?
        let def: ChannelConstants?

        enum CodingKeys: String, CodingKey {
            case off = "OFF"
            case def = "DEF"
        }
    }

    struct ChannelConstants: Codable, Equatable, Hashable {
        let muC: Double?
        let sdC: Double?
        let muE: Double?
        let sdE: Double?

        enum CodingKeys: String, CodingKey {
            case muC = "mu_C"
            case sdC = "sd_C"
            case muE = "mu_E"
            case sdE = "sd_E"
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case modelVersion
        case agingAlphaFit = "aging_alpha_fit"
        case theta, thetaOff, thetaDef, se, reliability
        case thetaZ = "theta_z"
        case thetaZOff = "theta_z_off"
        case thetaZDef = "theta_z_def"
        case seZ = "se_z"
        case seasonConstants = "season_constants"
        case weights, priorWeight, projection
        case thetaBySeason = "theta_by_season"
        case driftZ = "drift_z"
        case trajectoryMaxZ = "trajectory_max_z"
    }
}
