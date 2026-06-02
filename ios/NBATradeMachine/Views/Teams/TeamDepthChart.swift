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
