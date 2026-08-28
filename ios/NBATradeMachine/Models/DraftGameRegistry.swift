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
            availability: .available,   // Phase 4.5 — historical pool (familySixFlex)
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
            id: "blind-draft",
            title: "Blind Draft",
            subtitle: "Slot masked random players, then see who you drafted.",
            systemImage: "eye.slash.fill",
            availability: .available,   // Phase 2 — blind-info + reroll modifiers
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "budget-builder",
            title: "Budget Builder",
            subtitle: "Draft five under a cap — one per team, stars cost more.",
            systemImage: "tag.fill",
            availability: .available,   // Phase 2.1 — tier-price budget + one-per-team
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 8,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "create-a-player",
            title: "Create-A-Player",
            subtitle: "Draft a Scorer, Defender, Playmaker & Do-It-All — best composite wins.",
            systemImage: "wand.and.stars",
            availability: .available,   // Phase 8 — COMPOSITE_BUILDER (slotMetric scoring)
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 8,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "best-1990s-draft",
            title: "Best 90s Draft (1996+)",   // Sol: relabel — data floor is 1996-97
            subtitle: "Draft from the late-90s player pool.",
            systemImage: "clock.arrow.circlepath",
            availability: .available,   // Phase 4.5 — historical pool (familyFive)
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        // Phase 4.5 — new historical cards (ids match HistoricalPresets).
        DraftGame(
            id: "all-decade-2000s",
            title: "All-Decade 2000s",
            subtitle: "Draft the best of the 2000s.",
            systemImage: "calendar",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "all-decade-2010s",
            title: "All-Decade 2010s",
            subtitle: "Draft the best of the 2010s.",
            systemImage: "calendar",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "all-time-best-five",
            title: "All-Time Best Five",
            subtitle: "Draft five from every eligible season since 1996-97.",
            systemImage: "trophy.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "champions-draft",
            title: "Champions Draft",
            subtitle: "Only players who won a ring.",
            systemImage: "medal.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "mvp-club",
            title: "MVP Club",
            subtitle: "Draft from the MVP winners only.",
            systemImage: "crown.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 6,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "all-nba-draft",
            title: "All-NBA Draft",
            subtitle: "Draft from All-NBA selections.",
            systemImage: "star.circle.fill",
            availability: .available,
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
            availability: .available,   // Phase 2 — economy modifier (real-salary budget)
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 12,
                                            allowsCPU: true, allowsLocalFriends: true)
        ),
        DraftGame(
            id: "rank-players",
            title: "Rank Players",
            subtitle: "Order eight stars — how close to the model can you get?",
            systemImage: "list.number",
            availability: .available,   // Phase 3 — CLASSIFICATION
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "tier-list",
            title: "Tier List",
            subtitle: "Sort twelve players into S–D tiers.",
            systemImage: "square.stack.3d.up.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "start-bench-cut",
            title: "Start / Bench / Cut",
            subtitle: "Three players, three fates.",
            systemImage: "figure.basketball",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "bigger-contract",
            title: "Bigger Contract",
            subtitle: "Higher or lower — who's paid more? Build a streak.",
            systemImage: "dollarsign.arrow.circlepath",
            availability: .available,   // Phase 3 — COMPARE
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "higher-rated",
            title: "Higher Rated",
            subtitle: "Who's the better player? Keep the streak alive.",
            systemImage: "chart.line.uptrend.xyaxis",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        // Phase 8 — BRACKET (new subjective-pick single-elimination engine).
        DraftGame(
            id: "best-player-bracket",
            title: "Best Player Bracket",
            subtitle: "Seed 16 stars and crown a champion, one matchup at a time.",
            systemImage: "trophy.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "position-bracket",
            title: "Position Bracket",
            subtitle: "An 8-player bracket — pick your winner each round.",
            systemImage: "list.bullet.indent",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
        DraftGame(
            id: "quick-bracket",
            title: "Quick Bracket",
            subtitle: "Four random players, three quick calls, one champion.",
            systemImage: "bolt.fill",
            availability: .available,
            capabilities: SetupCapabilities(minHumans: 1, maxParticipants: 1,
                                            allowsCPU: false, allowsLocalFriends: false)
        ),
    ]

    /// Lookup by id (used by the store + setup screen). nil for an unknown id.
    static func game(_ id: String) -> DraftGame? { all.first { $0.id == id } }
}
