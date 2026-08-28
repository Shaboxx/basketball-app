import Foundation

/// How a draft game is played. `.online` (Phase 7) is server-authoritative real-time
/// multiplayer over a `gameSessions/{id}` doc; it ships DARK behind
/// `AppConfig.onlineGamesEnabled` (the setup screen only offers it when that flag AND the
/// game's `SetupCapabilities.allowsOnline` are both true). The raw values are the persisted
/// form, so `.online` appends without disturbing older stored blobs.
nonisolated enum PlayMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case localFriends   // pass-and-play on one device
    case soloVsCPU
    case online         // Phase 7 — real-time multiplayer via a join code
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .localFriends: return "Local Pass-and-Play"
        case .soloVsCPU:    return "Solo vs CPU"
        case .online:       return "Online with Friends"
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
    /// Phase 7: whether this game may be played ONLINE (server-authoritative multiplayer).
    /// Additive with a default so every existing `SetupCapabilities(...)` call site is
    /// unchanged; the setup screen still gates the actual entry behind
    /// `AppConfig.onlineGamesEnabled`, so `true` here alone never surfaces online while dark.
    var allowsOnline: Bool = false

    /// The hard product ceiling on total participants, regardless of config.
    static let hardCap = 15

    /// Memberwise init kept explicit so the additive `allowsOnline` defaults to false — every
    /// prior call site (which passes the first four labels) compiles unchanged.
    init(minHumans: Int, maxParticipants: Int, allowsCPU: Bool,
         allowsLocalFriends: Bool, allowsOnline: Bool = false) {
        self.minHumans = minHumans
        self.maxParticipants = maxParticipants
        self.allowsCPU = allowsCPU
        self.allowsLocalFriends = allowsLocalFriends
        self.allowsOnline = allowsOnline
    }

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
