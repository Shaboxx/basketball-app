import Foundation
/// v2 impact (written by scripts/upload_theta_v2.py).
/// Optional — docs without it decode nil. `theta` is the canonical headline rating (SwishScore).
struct ThetaV2: Codable, Equatable, Hashable {
    let combined: Double?
    let off: Double?
    let def: Double?
    let l2Signed: Double?
    /// Canonical headline SwishScore rating (combined post-cutover). Nil when unavailable — show "—".
    let theta: Double?
    /// Axis tag from backend meta (e.g. "theta"). Nil for older docs.
    let headlineAxis: String?
}
