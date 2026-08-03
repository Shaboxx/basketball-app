import SwiftUI

/// A compact 0-100 "overall" rating badge — a legible reference frame for the raw signed σ
/// value (which has no scale on its own). Percentile-based (higher = better vs. the league),
/// the familiar Madden/2K/ESPN idiom. Tinted by tier (green standout → red liability) with the
/// number ALWAYS shown, so color is never the sole cue (WCAG).
struct ValueGradeBadge: View {
    let grade: Int
    /// Optional caption shown under the badge (e.g. a compact OFF/DEF breakdown).
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(grade)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Self.color(grade))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Self.color(grade).opacity(0.15), in: Capsule())
            if let caption {
                Text(caption)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SwishScore rating \(grade) of 100" + (caption.map { ", \($0)" } ?? ""))
    }

    /// Tier color for a 0-100 grade — green standouts, red liabilities, neutral around the
    /// league midpoint. Reused wherever a grade is rendered.
    static func color(_ grade: Int) -> Color {
        switch grade {
        case 70...:   return .green
        case 45..<70: return .secondary
        case 30..<45: return .orange
        default:      return .red
        }
    }
}
