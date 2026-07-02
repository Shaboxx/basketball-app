import SwiftUI

/// Reusable one-side trade verdict: net fantasy value, then either an fp/game
/// delta (points formats) or the per-category swing bars, then the plain-language
/// flags. Shared by the propose + review surfaces so the verdict reads identically.
struct FantasyTradeVerdictCard: View {
    let title: String
    let swing: FantasyTradeSwing
    let format: FantasyFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack {
                Text("Net fantasy value").foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.2f", swing.netValue))
                    .monospacedDigit().bold()
                    .foregroundStyle(swing.netValue >= 0 ? .green : .red)
            }
            if format.isPoints, let fp = swing.fpPerGameDelta {
                HStack {
                    Text("Projected fantasy pts/game").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.1f", fp))
                        .monospacedDigit().bold()
                        .foregroundStyle(fp >= 0 ? .green : .red)
                }
            } else {
                Divider()
                ForEach(FantasyCategoryOrder.ordered(swing.categoryDelta), id: \.label) { item in
                    CategoryBarRow(label: item.label, z: item.z)
                }
            }
            Divider()
            ForEach(swing.flags, id: \.self) { flag in
                HStack(spacing: 8) {
                    Image(systemName: icon(flag.kind)).foregroundStyle(color(flag.kind))
                    Text(flag.text).font(.caption)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func icon(_ k: FantasyTradeFlag.Kind) -> String {
        switch k {
        case .gain: return "checkmark.circle.fill"
        case .loss: return "minus.circle.fill"
        case .neutral: return "equal.circle.fill"
        }
    }
    private func color(_ k: FantasyTradeFlag.Kind) -> Color {
        switch k {
        case .gain: return .green
        case .loss: return .red
        case .neutral: return .gray
        }
    }
}
