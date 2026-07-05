import Foundation

/// A compact, shareable snapshot of a trade's moving parts — enough to RE-LOAD
/// a shared trade on another device (NAV-21) with no URL scheme, domain, or
/// server. Players and teams are referenced by id and re-resolved locally, so
/// the full `Team`/`Player` objects are NOT embedded (that would make the code
/// enormous and un-pasteable).
struct TradeCode: Codable, Equatable {
    let v: Int
    let teamIds: [String]
    let movements: [Move]
    let picks: [PickMove]
    let cash: [String: Int]
    let offseason: Bool

    struct Move: Codable, Equatable { let p: String; let from: String; let to: String }
    struct PickMove: Codable, Equatable { let pick: Pick; let from: String; let to: String }

    init(trade: Trade, offseason: Bool) {
        self.v = 1
        self.teamIds = trade.teams.map(\.teamId)
        self.movements = trade.movements.map {
            Move(p: $0.playerId, from: $0.fromTeamId, to: $0.toTeamId)
        }
        self.picks = trade.pickMovements.map {
            PickMove(pick: $0.pick, from: $0.fromTeamId, to: $0.toTeamId)
        }
        self.cash = trade.cashSent
        self.offseason = offseason
    }
}

/// Encodes/decodes a `TradeCode` to a copy-pasteable token. The token carries a
/// version prefix so it can be spotted inside a larger pasted message.
enum TradeCodec {
    static let prefix = "NBATM1:"

    static func encode(_ code: TradeCode) -> String? {
        guard let data = try? JSONEncoder().encode(code) else { return nil }
        return prefix + data.base64EncodedString()
    }

    /// Pull a code out of arbitrary pasted text (the user may paste the whole
    /// message). Returns nil when no valid token is present.
    static func decode(_ text: String) -> TradeCode? {
        guard let r = text.range(of: prefix) else { return nil }
        // The base64 token runs from just after the prefix to the next
        // whitespace/newline (base64 itself contains no whitespace).
        let tail = text[r.upperBound...]
        let token = String(tail.prefix { !$0.isWhitespace })
        guard !token.isEmpty,
              let data = Data(base64Encoded: token),
              let code = try? JSONDecoder().decode(TradeCode.self, from: data)
        else { return nil }
        return code
    }
}
