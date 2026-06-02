import Foundation

/// Phase 7e composite valuation block ("comp-Z"): joins Phase 7 v2 latent
/// value (theta_z), Phase 7b cost ensemble, Phase 7c value cone, and
/// Phase 7d asset / verdict / trust into one per-player surface that
/// downstream UI can consume without reaching into the individual phases.
///
/// All fields decode as nil when the source JSON omits them so old player
/// documents (pre-phase-7e join) continue to work.
struct CompZValuation: Codable, Equatable, Hashable {
    /// Schema version of the comp-Z block; bumped when the join contract
    /// changes (Phase 7e plan §3).
    let version: String?

    /// Composite z-score (Phase 7e §4.1) — single scalar used as the
    /// primary list sort key in trade and asset views.
    let score: Double?

    /// Role label assigned by Phase 7e role classifier (e.g. "Lead Guard").
    let role: String?

    /// Annual cost cone in dollars (Phase 7b ensemble).
    let cost: ValueCone?

    /// Annual value cone in dollars (Phase 7c v2 isotonic cap_pct on theta_z).
    let value: ValueCone?

    /// Asset summary (Phase 7d): dollars-point + tier label.
    let asset: AssetSummary?

    /// Human-readable verdict ("Fair at Point", "Discount", "Premium", …).
    let verdict: String?

    /// Trust audit (Phase 7d): 0-6 score + 6 flag set.
    let trust: TrustReport?

    /// Annual dollar cone (floor / point / ceiling). All values are
    /// total dollars for the season (not cap%).
    struct ValueCone: Codable, Equatable, Hashable {
        let floorDollars: Int?
        let pointDollars: Int?
        let ceilingDollars: Int?
    }

    /// Asset valuation: dollars-point (value − cost) and tier label.
    /// Tier enum mirrors the Phase 7d thresholds in cba_constants.py.
    struct AssetSummary: Codable, Equatable, Hashable {
        let dollarsPoint: Int?
        let tier: Tier?

        enum Tier: String, Codable, Equatable, Hashable {
            case tradeChip = "trade_chip"
            case plus
            case neutral
            case minus
            case dead
        }
    }

    /// Trust report (Phase 7d 6-flag scorer).
    struct TrustReport: Codable, Equatable, Hashable {
        let score: Int?
        let flags: TrustFlags?
    }

    struct TrustFlags: Codable, Equatable, Hashable {
        let costZero: Bool?
        let modelUnreliable: Bool?
        let outlierAsset: Bool?
        let value2xCost: Bool?
        let staleStats: Bool?
        let freeAgent: Bool?
    }
}
