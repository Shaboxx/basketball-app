import Foundation

/// Pure serializer turning a validated trade into a multi-line text summary
/// suitable for messaging/email shares ("Pistons receive: …; Bucks receive: …").
///
/// The output is deterministic given the inputs (teams are listed in the
/// trade's declared order; players/picks in trade.movement order) so the
/// text remains snapshot-testable and stable for share-sheet previews.
enum TradeShareText {

    /// One-shot rendering. Returns a string with one "TEAM receives:" block
    /// per team plus, optionally, the rollup metrics for each team.
    static func render(
        _ trade: Trade,
        playersById: [String: Player],
        includeRollup: Bool = true
    ) -> String {
        let confirmation = TradeConfirmation.build(
            trade: trade, playersById: playersById
        )
        var out: [String] = []
        for pkg in confirmation.teams {
            out.append(renderTeam(pkg, includeRollup: includeRollup))
        }
        return out.joined(separator: "\n\n")
    }

    private static func renderTeam(
        _ pkg: TradeConfirmation.TeamPackage,
        includeRollup: Bool
    ) -> String {
        var lines: [String] = ["\(pkg.team.fullName.uppercased()) receive:"]
        for player in pkg.incomingPlayers {
            lines.append("• \(player.name)")
        }
        for pick in pkg.incomingPicks {
            lines.append("• \(pick.shortLabel)")
        }
        if pkg.cashOutgoing > 0 {
            lines.append("• Cash: \(formatDollars(pkg.cashOutgoing))")
        }
        if pkg.incomingPlayers.isEmpty
            && pkg.incomingPicks.isEmpty
            && pkg.cashOutgoing == 0 {
            lines.append("• (nothing)")
        }
        if includeRollup {
            if let summary = rollupSummary(for: pkg.rollup) {
                lines.append("")
                lines.append(summary)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func rollupSummary(
        for rollup: TradeConfirmation.Rollup
    ) -> String? {
        var parts: [String] = []
        if let d = rollup.assetDeltaDollars {
            parts.append("Asset Δ \(formatSignedDollars(d))")
        }
        if let z = rollup.offDeltaLeagueZ {
            parts.append("OFF Δ \(formatSignedZ(z))σ")
        }
        if let z = rollup.defDeltaLeagueZ {
            parts.append("DEF Δ \(formatSignedZ(z))σ")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func formatDollars(_ value: Int) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return String(format: "$%.2fM", millions)
        }
        if abs >= 1_000 {
            let thousands = Double(value) / 1_000
            return String(format: "$%.0fK", thousands)
        }
        return "$\(value)"
    }

    private static func formatSignedDollars(_ value: Int) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(formatDollars(Swift.abs(value)))"
    }

    private static func formatSignedZ(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return String(format: "\(sign)%.2f", Swift.abs(value))
    }
}
