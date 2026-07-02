import Foundation

/// One roster slot bucket. Raw-value Codable so it persists inside the local
/// `FantasyTeam` JSON blob (UserDefaults) without migration machinery.
nonisolated enum FantasySlot: String, Codable, CaseIterable, Identifiable {
    case lineup, bench, ir

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lineup: return "Lineup"
        case .bench:  return "Bench"
        case .ir:     return "IR"
        }
    }
}

/// User-configurable roster shape (AppSettings-backed). The default is the
/// standard fantasy divide: 10 lineup · 3 bench · 1 injury-reserve.
nonisolated struct FantasyRosterLimits: Equatable {
    var lineup: Int
    var bench: Int
    var ir: Int

    static let standard = FantasyRosterLimits(lineup: 10, bench: 3, ir: 1)
    var total: Int { lineup + bench + ir }

    func cap(_ slot: FantasySlot) -> Int {
        switch slot {
        case .lineup: return lineup
        case .bench:  return bench
        case .ir:     return ir
        }
    }
}

/// Pure slot resolution over a roster: stored user choices are honored (in roster
/// order) up to each slot's cap; everyone unassigned auto-fills lineup → bench → IR
/// in roster order — so a fresh team lands exactly on the standard divide. Players
/// beyond every cap stay VISIBLE on the bench (the view flags the over-limit count)
/// rather than vanishing.
nonisolated enum FantasyRosterSlots {

    static func effectiveAssignments(roster: [String],
                                     stored: [String: FantasySlot],
                                     limits: FantasyRosterLimits) -> [String: FantasySlot] {
        var counts: [FantasySlot: Int] = [.lineup: 0, .bench: 0, .ir: 0]
        var out: [String: FantasySlot] = [:]

        // Pass 1 — honor stored assignments in roster order while they fit.
        for slug in roster {
            guard let want = stored[slug] else { continue }
            if counts[want, default: 0] < limits.cap(want) {
                out[slug] = want
                counts[want, default: 0] += 1
            }
        }
        // Pass 2 — auto-fill the rest lineup → bench → IR; overflow stays on the bench.
        for slug in roster where out[slug] == nil {
            let target: FantasySlot
            if counts[.lineup, default: 0] < limits.lineup { target = .lineup }
            else if counts[.bench, default: 0] < limits.bench { target = .bench }
            else if counts[.ir, default: 0] < limits.ir { target = .ir }
            else { target = .bench }
            out[slug] = target
            counts[target, default: 0] += 1
        }
        return out
    }

    /// The roster's slugs assigned to `slot`, preserving roster order.
    static func slugs(in slot: FantasySlot, roster: [String],
                      assignments: [String: FantasySlot]) -> [String] {
        roster.filter { assignments[$0] == slot }
    }
}
