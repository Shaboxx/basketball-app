import SwiftUI

struct DepthSlot: Identifiable, Hashable {
    let player: Player
    let bestPosition: String
    let secondaryPositions: [String]   // canonical, excludes bestPosition
    let total: Double?                  // v2 display total (dispTotal)
    let off: Double?                    // v2 display offense (dispOff)
    let def: Double?                    // v2 display defense (dispDef)
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

    /// Per-player view used by the layer-based assignment.
    private struct Profile {
        let slot: DepthSlot
        let primary: String          // canonical ESPN primary (a valid column)
        let eligible: [String]       // canonical eligible columns (incl. primary)
        let total: Double?           // dispTotal; nil sorts last
        var id: String { slot.player.id }
    }

    /// Layer-based two-pass assignment. Pass 1 fills each position's column
    /// top-down with the players whose PRIMARY is that position (best total at
    /// the top). Pass 2 backfills empty cells with adjacent-eligible players,
    /// never placing a player twice on the same layer or twice in the same
    /// column. `overflow` per position reflects extra PRIMARIES that didn't fit.
    static func columns(for roster: [Player], cap: Int = 4) -> [String: ColumnResult] {
        // 1. Build profiles; skip players without a canonical primary column.
        var profiles: [Profile] = []
        for p in roster {
            guard let role = roleProfile(p) else { continue }
            guard positions.contains(role.best) else { continue }
            let eligible = role.columns.filter { positions.contains($0) }
            let slot = DepthSlot(
                player: p,
                bestPosition: role.best,
                secondaryPositions: role.secondaries,
                total: p.dispTotal,
                off: p.dispOff,
                def: p.dispDef
            )
            profiles.append(Profile(slot: slot, primary: role.best,
                                    eligible: eligible, total: p.dispTotal))
        }

        // Stable ordering helper: total desc (nil last), then name.
        func better(_ a: Profile, _ b: Profile) -> Bool {
            let av = a.total ?? -.greatestFiniteMagnitude
            let bv = b.total ?? -.greatestFiniteMagnitude
            if av != bv { return av > bv }
            return a.slot.player.name < b.slot.player.name
        }

        // grid[pos][layer] = assigned Profile (nil = empty cell)
        var grid: [String: [Profile?]] = [:]
        for pos in positions { grid[pos] = Array(repeating: nil, count: cap) }
        var placedOnLayer: [Set<String>] = Array(repeating: [], count: cap)
        var placedAtPos: [String: Set<String>] = [:]
        for pos in positions { placedAtPos[pos] = [] }
        var primaryCount: [String: Int] = [:]

        // 2. Pass 1 — primaries.
        var byPrimary: [String: [Profile]] = [:]
        for p in profiles { byPrimary[p.primary, default: []].append(p) }
        for pos in positions {
            let group = (byPrimary[pos] ?? []).sorted(by: better)
            primaryCount[pos] = group.count
            for (layer, prof) in group.enumerated() where layer < cap {
                grid[pos]?[layer] = prof
                placedOnLayer[layer].insert(prof.id)
                placedAtPos[pos]?.insert(prof.id)
            }
        }

        // 3. Pass 2 — adjacent depth fill, layer by layer.
        let sortedProfiles = profiles.sorted(by: better)
        for layer in 0..<cap {
            for pos in positions where grid[pos]?[layer] == nil {
                guard let pick = sortedProfiles.first(where: { prof in
                    prof.eligible.contains(pos)
                        && !placedOnLayer[layer].contains(prof.id)
                        && !(placedAtPos[pos]?.contains(prof.id) ?? false)
                }) else { continue }
                grid[pos]?[layer] = pick
                placedOnLayer[layer].insert(pick.id)
                placedAtPos[pos]?.insert(pick.id)
            }
        }

        // 4. Build ColumnResult per position.
        var result: [String: ColumnResult] = [:]
        for pos in positions {
            let shown = (grid[pos] ?? []).compactMap { $0?.slot }
            let overflow = max(0, (primaryCount[pos] ?? 0) - shown.count)
            result[pos] = ColumnResult(shown: shown, overflow: overflow)
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
            Text(valueLine).font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
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

    /// v2 value summary: TOT / OFF / DEF, one stat per line so it stays
    /// legible inside the narrow column cell.
    private var valueLine: String {
        "TOT \(Player.fmtVal(slot.total))\nOFF \(Player.fmtVal(slot.off))\nDEF \(Player.fmtVal(slot.def))"
    }
}
