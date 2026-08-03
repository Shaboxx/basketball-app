import Foundation

/// How a draft game is played. Online multiplayer is DEFERRED (scope F5) — the
/// scaffold ships local pass-and-play + solo-vs-CPU only.
nonisolated enum PlayMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case localFriends   // pass-and-play on one device
    case soloVsCPU
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .localFriends: return "Local Pass-and-Play"
        case .soloVsCPU:    return "Solo vs CPU"
        }
    }
}

/// The badge shown on a hub card + the pure resolution result.
nonisolated enum AvailabilityBadge: Equatable { case available, seasonal, comingSoon }

nonisolated struct AvailabilityState {
    let isPlayable: Bool
    let disabledReason: String?    // nil when playable
    let badge: AvailabilityBadge
}

/// When a game may be entered. Resolution is PURE against an injected `now`
/// (no ambient Date); seasonal boundaries are inclusive.
nonisolated enum GameAvailability {
    case available
    case seasonal(start: Date, end: Date, reason: String)
    case comingSoon(reason: String)

    func resolve(now: Date) -> AvailabilityState {
        switch self {
        case .available:
            return AvailabilityState(isPlayable: true, disabledReason: nil, badge: .available)
        case let .comingSoon(reason):
            return AvailabilityState(isPlayable: false, disabledReason: reason, badge: .comingSoon)
        case let .seasonal(start, end, reason):
            let inWindow = now >= start && now <= end     // inclusive both ends
            return AvailabilityState(isPlayable: inWindow,
                                     disabledReason: inWindow ? nil : reason,
                                     badge: .seasonal)
        }
    }
}

/// Participant limits for a game's setup screen. CPUs count WITHIN the cap.
nonisolated struct SetupCapabilities: Equatable {
    let minHumans: Int          // ≥1
    let maxParticipants: Int    // combined humans + CPUs
    let allowsCPU: Bool
    let allowsLocalFriends: Bool

    /// The hard product ceiling on total participants, regardless of config.
    static let hardCap = 15

    /// Effective cap: `maxParticipants`, never above `hardCap`, never below `minHumans`.
    var effectiveCap: Int { min(max(maxParticipants, max(minHumans, 1)), Self.hardCap) }

    /// Clamp a requested (humans, cpus) pair to the capabilities. Humans are
    /// honored first (floored at `minHumans`, capped at the effective cap); CPUs
    /// then absorb whatever room is left, and drop to 0 when CPUs aren't allowed.
    func clamp(humans: Int, cpus: Int) -> (humans: Int, cpus: Int) {
        let cap = effectiveCap
        let floor = max(minHumans, 1)
        let h = min(max(humans, floor), cap)
        guard allowsCPU else { return (h, 0) }
        let room = cap - h
        let c = min(max(cpus, 0), room)
        return (h, c)
    }
}
