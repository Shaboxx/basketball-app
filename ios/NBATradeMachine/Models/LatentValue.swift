import Foundation

/// Phase 7 v2 latent player value (theta-hat): the fused CraftedPM + EPM
/// latent impact in points / 100 possessions, plus its uncertainty and,
/// for Tier-B players, a multi-season projection.
///
/// Written to `players/{slug}.latentValue` by scripts/upload_latent_value.py.
/// All fields are optional so docs without latent-value data decode as nil,
/// and so a Tier-A doc (weights + priorWeight, no projection) and a Tier-B doc
/// (projection, no weights/priorWeight) both decode cleanly.
struct LatentValue: Codable, Equatable, Hashable {
    let version: String?
    let theta: Double?
    let thetaOff: Double?
    let thetaDef: Double?
    let se: Double?
    let reliability: Double?
    let weights: Weights?          // Tier A only
    let priorWeight: Int?          // Tier A only
    let projection: [Projection]?  // Tier B only

    /// Crafted vs. EPM blend weights (Tier A fusion). Sum to ~1.
    struct Weights: Codable, Equatable, Hashable {
        let crafted: Double?
        let epm: Double?
    }

    /// One projected future season (Tier B): theta with growing uncertainty.
    struct Projection: Codable, Equatable, Hashable {
        let season: String?
        let theta: Double?
        let se: Double?
    }

    enum CodingKeys: String, CodingKey {
        case version, theta, thetaOff, thetaDef, se, reliability
        case weights, priorWeight, projection
    }
}
