import Foundation
/// v2 impact (written by scripts/upload_theta_v2.py). Optional — docs without it decode nil.
struct ThetaV2: Codable, Equatable, Hashable {
    let combined: Double?
    let off: Double?
    let def: Double?
    let l2Signed: Double?
}
