import SwiftUI

/// Title-cases a canonical slug ("jaren-jackson-jr." -> "Jaren Jackson Jr.")
/// for id-only fields the SP5 output doesn't carry a name for.
func offseasonDisplayName(_ slug: String) -> String {
    let cleaned = slug.hasSuffix(".") ? String(slug.dropLast()) : slug
    let words = cleaned.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
    return words.joined(separator: " ")
}

struct TransactionRow: View {
    let txn: OffseasonTransaction

    var body: some View {
        switch txn {
        case .fa(let f): faRow(f)
        case .trade(let t): tradeRow(t)
        case .unknown:
            Label("Unrecognized transaction", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func faRow(_ f: FATxn) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name ?? f.playerId.map(offseasonDisplayName) ?? "—")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 4) {
                    Text(faTypeLabel(f.type)).font(.caption2).foregroundStyle(.secondary)
                    if let t = f.team { Text("→ \(t)").font(.caption2) }
                    if let y0 = f.firstYear, let yr = f.years {
                        Text("· \(dollars(y0)) × \(yr)y").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            sourceBadge(f.source)
        }
    }

    @ViewBuilder private func tradeRow(_ t: TradeTxn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Text(t.teams.isEmpty ? "Trade" : t.teams.joined(separator: " ↔ "))
                    .font(.callout.weight(.semibold))
                Spacer()
                sourceBadge(t.source)
            }
            ForEach(Array(t.players.enumerated()), id: \.offset) { _, p in
                let nm = p.name ?? offseasonDisplayName(p.playerId)
                Text("• \(nm)\(p.to.map { " → \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func sourceBadge(_ s: TxnSource) -> some View {
        if s == .ai {
            Text("AI").font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.tint, in: Capsule()).foregroundStyle(.white)
        }
    }

    private func faTypeLabel(_ t: String) -> String {
        switch t {
        case "sign": return "Signed"
        case "re_sign": return "Re-signed"
        case "exercise_option": return "Option exercised"
        case "decline_option": return "Option declined"
        case "extend_qo": return "Qualifying offer"
        default: return t
        }
    }

    private func dollars(_ v: Int) -> String { "$\(v / 1_000_000)M" }
}
