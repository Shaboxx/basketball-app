import Foundation

/// The static catalogue of draft-game variants. Everything ships as a disabled
/// "Coming Soon" card (F7) so the hub hierarchy + badges + registry are exercised
/// from day one; the NBA-draft-guess ships `.seasonal` to exercise the date-range
/// branch. No remote config. As real games are built, flip an entry's
/// `availability` to `.available`.
nonisolated enum DraftGameRegistry {

    /// Concrete example window for the draft-guess: from the day after the 2026
    /// Finals through the 2027 NBA Draft (placeholder dates — the real game will
    /// resolve these from the league calendar when it is built).
    private static func iso(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    static let all: [DraftGame] = [
        DraftGame(
            id: "best-6man-2020s",
            title: "Best 6-Man 2020s",
            subtitle: "Draft a six-man rotation from the 2020s.",
            systemImage: "person.3.fill",
            availability: .comingSoon(reason: "Coming soon"),
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "best-current-players",
            title: "Best Current Players",
            subtitle: "Draft the best active roster head-to-head.",
            systemImage: "star.fill",
            availability: .available,   // first live game — ROSTER_CONSTRUCTION engine (Phase 1)
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 8,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "best-1990s-draft",
            title: "Best 1990s Draft",
            subtitle: "Draft from the 1990s player pool.",
            systemImage: "clock.arrow.circlepath",
            availability: .comingSoon(reason: "Coming soon"),
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "nba-draft-guess",
            title: "NBA Draft Guess",
            subtitle: "Predict the real NBA Draft — open around draft season.",
            systemImage: "questionmark.circle.fill",
            availability: .seasonal(start: iso("2026-06-20T00:00:00Z"),
                                    end: iso("2027-06-25T00:00:00Z"),
                                    reason: "Opens around NBA Draft season"),
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 10,
                                            allowsCPU: false, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "fantasy-draft",
            title: "Fantasy Draft",
            subtitle: "Snake-draft a fantasy roster with friends.",
            systemImage: "list.number",
            availability: .comingSoon(reason: "Coming soon"),
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 12,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "fantasy-salary-cap",
            title: "Fantasy Salary Cap",
            subtitle: "Build a fantasy roster under a salary cap.",
            systemImage: "dollarsign.circle.fill",
            availability: .comingSoon(reason: "Coming soon"),
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 12,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
    ]

    /// Lookup by id (used by the store + setup screen). nil for an unknown id.
    static func game(_ id: String) -> DraftGame? { all.first { $0.id == id } }
}
