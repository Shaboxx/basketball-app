import Foundation

/// Per-100-possession impact from the NN player-evaluation board (θ-NN rev 3, nowcast build).
/// Written by the thetaboard pipeline; all fields optional — Firestore docs without the map
/// decode as nil; fields omitted (not null) when absent.
///
/// - `off`, `def`, `total`: points per 100 possessions (off + def = total by construction).
/// - `poss`: possession count used to compute the ratings.
/// - `rookie`: player is in their first NBA season (flag; thin data warning may apply).
/// - `disagree`: possession model and box-outcome stack are >1.5σ apart (disagreement is information).
/// - `blend`: Model B3 outcome-calibrated stack value (different estimand, kept separate from total).
/// - `epm`: external EPM reference value if available.
/// - `lastTotal`: total from the frozen projection (before current-season fit).
/// - `projTotal`: projected next-season total.
/// - `availShare`: projected 2026-27 games-played share in [0, 1].
struct ThetaBoardValue: Codable, Equatable, Hashable {
    let off: Double?
    let def: Double?
    let total: Double?
    let poss: Int?
    let rookie: Bool?
    let disagree: Bool?
    let blend: Double?
    let epm: Double?
    let lastTotal: Double?
    let projTotal: Double?
    let availShare: Double?
}
