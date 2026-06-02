import Foundation

/// SP1 position-eligibility block written to players/{slug}.positionEligibility
/// by scripts/upload_position_eligibility.py. Optional on Player — docs predating
/// the upload decode as nil and the depth chart falls back to listed position.
struct PositionEligibility: Codable, Equatable, Hashable {
    let primary: String?
    let eligible: [Slot]

    struct Slot: Codable, Equatable, Hashable {
        let position: String
        let fitScore: Double?
    }
}
