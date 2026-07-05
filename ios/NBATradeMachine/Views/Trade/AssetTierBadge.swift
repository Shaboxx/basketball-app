import SwiftUI

/// Colored capsule for a Phase-7d ASSET tier (trade_chip / plus / neutral /
/// minus / dead). This is a DIFFERENT axis from the Trade Value letter grade
/// rendered by `TradeTierBadge` — the asset tier comes from the comp-Z
/// dollars-point (value − cost), not the A+…F trade-value composite.
struct AssetTierBadge: View {
    let tier: CompZValuation.AssetSummary.Tier

    var body: some View {
        // Tinted style (like TradeTierBadge): white-on-saturated-green/teal/gray/orange fills
        // failed WCAG contrast.
        Text(Self.label(for: tier))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Self.color(for: tier).opacity(0.18), in: Capsule())
            .foregroundStyle(Self.color(for: tier))
    }

    /// Human-readable label for each tier. Pure mapping kept static so it can
    /// be unit-tested without rendering the view.
    static func label(for tier: CompZValuation.AssetSummary.Tier) -> String {
        switch tier {
        case .tradeChip: return "Trade Chip"
        case .plus:      return "Plus"
        case .neutral:   return "Neutral"
        case .minus:     return "Minus"
        case .dead:      return "Dead"
        }
    }

    /// Capsule fill color for each tier. Pure mapping kept static so it can be
    /// unit-tested without rendering the view.
    static func color(for tier: CompZValuation.AssetSummary.Tier) -> Color {
        switch tier {
        case .tradeChip: return .green
        case .plus:      return .teal
        case .neutral:   return .gray
        case .minus:     return .orange
        case .dead:      return .red
        }
    }
}
