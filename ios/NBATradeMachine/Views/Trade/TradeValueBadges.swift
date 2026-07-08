import SwiftUI

/// Colored capsule for a Trade Value tier grade (A+ … F).
struct TradeTierBadge: View {
    let tier: String
    var body: some View {
        Text(tier)
            .font(.caption2.weight(.bold))   // scales with Dynamic Type (was fixed 10pt)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Self.color(tier).opacity(0.18), in: Capsule())
            .foregroundStyle(Self.color(tier))
    }
    static func color(_ t: String) -> Color {
        switch t.first {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        case "D": return .red
        case "F": return .red        // worst tier must not read calmer than D
        default:  return .secondary   // unknown
        }
    }
}

/// Compact OE/DD chips from tradeValue.tags.
struct EngineChips: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 3) {
            if tags.contains("Offensive Engine") { chip("OE", .orange) }
            if tags.contains("Defensive Dynamo") { chip("DD", .purple) }
        }
    }
    private func chip(_ s: String, _ c: Color) -> some View {
        Text(s).font(.caption2.weight(.bold))   // scales with Dynamic Type (was fixed 8pt)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(c.opacity(0.18), in: Capsule()).foregroundStyle(c)
    }
}
