import Foundation

/// A non-player asset that can ride along in a fantasy trade: a future draft pick
/// or FAAB (free-agent-auction budget). Dynasty/keeper leagues trade picks as a
/// primary currency and redraft leagues trade FAAB, so a players-only tool can't
/// express the most common dynasty deal. Assets are DISPLAY-ONLY in the value
/// math for now (unvalued — they ride along in the row + note); a later pass can
/// fold a coarse pick value into netValue.
///
/// A struct (not an enum with associated values) so Codable is synthesized and the
/// UserDefaults blob stays trivially decodable. `id` gives SwiftUI list identity.
nonisolated struct FantasyTradeAsset: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable { case pick, faab }

    let id: UUID
    let kind: Kind
    let year: Int?     // pick only
    let round: Int?    // pick only
    let amount: Int?   // faab only

    init(id: UUID = UUID(), kind: Kind, year: Int? = nil, round: Int? = nil, amount: Int? = nil) {
        self.id = id; self.kind = kind; self.year = year; self.round = round; self.amount = amount
    }

    static func pick(year: Int, round: Int) -> FantasyTradeAsset {
        FantasyTradeAsset(kind: .pick, year: year, round: round)
    }
    static func faab(_ amount: Int) -> FantasyTradeAsset {
        FantasyTradeAsset(kind: .faab, amount: amount)
    }

    /// Short label for chips/rows, e.g. "2027 R1 pick" or "$50 FAAB".
    var display: String {
        switch kind {
        case .pick: return "\(year.map(String.init) ?? "?") R\(round ?? 0) pick"
        case .faab: return "$\(amount ?? 0) FAAB"
        }
    }

    /// A comma-joined summary of a side's assets (nil when empty), for appending to
    /// a "Team sends: …" line.
    static func summary(_ assets: [FantasyTradeAsset]) -> String? {
        assets.isEmpty ? nil : assets.map(\.display).joined(separator: ", ")
    }
}
