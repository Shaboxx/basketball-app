import Foundation
/// Team-relative trade value (written by scripts/upload_trade_value.py).
struct TradeValue: Codable, Equatable, Hashable {
    let tags: [String]?
    let scarcity: Double?
    let availability: Double?
    let ownTeam: String?
    let byTeam: [String: TeamEntry]?     // key = team tricode (e.g. "BOS")

    struct TeamEntry: Codable, Equatable, Hashable {
        let value: Double?
        let tier: String?
        let windowCenter: Double?
        let windowSlope: Double?
    }
    /// Convenience: entry for a receiving team's tricode (nil if absent).
    func forTeam(_ tricode: String) -> TeamEntry? { byTeam?[tricode] }
}
