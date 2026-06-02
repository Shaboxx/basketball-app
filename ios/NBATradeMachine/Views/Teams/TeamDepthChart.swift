import SwiftUI

struct DepthSlot: Identifiable, Hashable {
    let player: Player
    let bestPosition: String
    let secondaryPositions: [String]   // canonical, excludes bestPosition
    let thetaZ: Double?
    var id: String { player.id }
}

struct ColumnResult: Hashable {
    let shown: [DepthSlot]
    let overflow: Int
}

enum TeamDepthChartBuilder {
    static let positions = ["PG", "SG", "SF", "PF", "C"]

    static func canonical(_ raw: String) -> String? {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "PG", "SG", "SF", "PF", "C": return s
        case "G": return "PG"
        case "F": return "SF"
        case "F-C", "FC", "C-F", "CF": return "PF"
        case "G-F", "GF", "F-G", "FG": return "SF"
        default:
            let token = s.split(whereSeparator: { "-/ ".contains($0) })
                .first.map(String.init) ?? ""
            switch token {
            case "PG", "SG", "SF", "PF", "C": return token
            case "G": return "PG"
            case "F": return "SF"
            default: return nil
            }
        }
    }

    static func roleProfile(_ p: Player) -> (best: String, secondaries: [String], columns: [String])? {
        if let elig = p.positionEligibility,
           let primaryRaw = elig.primary, let best = canonical(primaryRaw) {
            let ordered = elig.eligible
                .sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
                .compactMap { canonical($0.position) }
            var columns: [String] = []
            for c in ordered where !columns.contains(c) { columns.append(c) }
            if !columns.contains(best) { columns.insert(best, at: 0) }
            let secondaries = columns.filter { $0 != best }
            return (best, secondaries, columns)
        }
        guard let best = canonical(p.position) else { return nil }
        return (best, [], [best])
    }

    static func columns(for roster: [Player], cap: Int = 4) -> [String: ColumnResult] {
        var buckets: [String: [DepthSlot]] = [:]
        for p in roster {
            guard let profile = roleProfile(p) else { continue }
            let slot = DepthSlot(
                player: p,
                bestPosition: profile.best,
                secondaryPositions: profile.secondaries,
                thetaZ: p.latentValue?.thetaZ
            )
            for col in profile.columns where positions.contains(col) {
                buckets[col, default: []].append(slot)
            }
        }
        var result: [String: ColumnResult] = [:]
        for pos in positions {
            let sorted = (buckets[pos] ?? []).sorted {
                let a = $0.thetaZ ?? -.greatestFiniteMagnitude
                let b = $1.thetaZ ?? -.greatestFiniteMagnitude
                if a != b { return a > b }
                return $0.player.name < $1.player.name
            }
            result[pos] = ColumnResult(
                shown: Array(sorted.prefix(cap)),
                overflow: max(0, sorted.count - cap)
            )
        }
        return result
    }
}

/// Depth-chart grid for a team page. Builds columns from the roster via
/// TeamDepthChartBuilder and renders 5 position columns, each capped, with a
/// "Best: <pos>" + dimmed-secondaries tag per cell. Designed to live inside a
/// List Section on TeamDetailView.
struct TeamDepthChartView: View {
    let roster: [Player]
    var cap: Int = 4

    private var columns: [String: ColumnResult] {
        TeamDepthChartBuilder.columns(for: roster, cap: cap)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(TeamDepthChartBuilder.positions, id: \.self) { pos in
                    Text(pos)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(TeamDepthChartBuilder.positions, id: \.self) { pos in
                    let col = columns[pos]
                    VStack(spacing: 4) {
                        if let col, !col.shown.isEmpty {
                            ForEach(col.shown) { slot in
                                NavigationLink(value: slot.player) {
                                    DepthSlotCell(slot: slot, column: pos)
                                }
                                .buttonStyle(.plain)
                            }
                            if col.overflow > 0 {
                                Text("+\(col.overflow) more")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        } else {
                            Text("—").font(.caption2).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.top, 6)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

private struct DepthSlotCell: View {
    let slot: DepthSlot
    let column: String

    var body: some View {
        VStack(spacing: 2) {
            Text(slot.player.name)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(sigma).font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text("Best: \(slot.bestPosition)")
                    .font(.system(size: 8).bold())
                ForEach(slot.secondaryPositions, id: \.self) { s in
                    Text(s.lowercased())
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color.black.opacity(0.06), lineWidth: 0.5))
    }

    private var sigma: String {
        slot.thetaZ.map { String(format: "%+.1fσ", $0) } ?? "—"
    }
}
