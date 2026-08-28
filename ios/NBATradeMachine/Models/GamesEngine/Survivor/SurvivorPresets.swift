import Foundation

/// SURVIVOR presets (spec §33 presets-as-data). Registry card id → the SURVIVOR
/// game its Start button launches. Computed `static var` — `GameConstraint`
/// (indirect enum) blocks automatic Sendable inference, same as the roster
/// presets.
nonisolated enum SurvivorPresets {

    static let nameAPlayerId = "survivor-name-a-player"   // current pool
    static let championsId = "survivor-champions"         // historical pool

    static let allIds: [String] = [nameAPlayerId, championsId]

    static func definition(for gameId: String) -> SurvivorDefinition? {
        switch gameId {
        case Self.nameAPlayerId: return nameAPlayer
        case Self.championsId:   return champions
        default:                 return nil
        }
    }

    // MARK: - Predicate helpers

    private static func positionIs(_ code: String) -> GameConstraint {
        .field(FieldConstraint(field: .position, op: .equal, value: .string(code)))
    }
    private static func awardAtLeast(_ field: GameField, _ n: Int) -> GameConstraint {
        .field(FieldConstraint(field: field, op: .greaterOrEqual, value: .number(Double(n))))
    }
    private static func decadeIs(_ year: Int) -> GameConstraint {
        .field(FieldConstraint(field: .decadeStartYear, op: .equal, value: .number(Double(year))))
    }

    // MARK: - Current-pool SURVIVOR (5-code positions are valid here)

    /// "Name a Guard / Wing-ish / Big" over the CURRENT pool, where the 5-code
    /// position is real. No-reuse elimination streak.
    static var nameAPlayer: SurvivorDefinition {
        SurvivorDefinition(
            id: Self.nameAPlayerId,
            title: "Name a Player",
            poolSource: .current,
            config: SurvivorConfig(
                prompts: [
                    SurvivorPrompt(id: "pos-pg", ask: "Name a Point Guard (PG)",
                                   predicate: positionIs("PG")),
                    SurvivorPrompt(id: "pos-sg", ask: "Name a Shooting Guard (SG)",
                                   predicate: positionIs("SG")),
                    SurvivorPrompt(id: "pos-sf", ask: "Name a Small Forward (SF)",
                                   predicate: positionIs("SF")),
                    SurvivorPrompt(id: "pos-pf", ask: "Name a Power Forward (PF)",
                                   predicate: positionIs("PF")),
                    SurvivorPrompt(id: "pos-c", ask: "Name a Center (C)",
                                   predicate: positionIs("C")),
                ],
                lives: 1))
    }

    // MARK: - Historical-pool SURVIVOR (family codes + awards/decades)

    /// "Name a champion / MVP / a player from a decade / a family" over the
    /// HISTORICAL pool. Position prompts use the collapsed FAMILY codes
    /// (GUARD/WING/BIG), never the 5-code position (would never match).
    static var champions: SurvivorDefinition {
        SurvivorDefinition(
            id: Self.championsId,
            title: "Survivor: Champions",
            poolSource: .historical(HistoricalFilter(minRating: 70)),
            config: SurvivorConfig(
                prompts: [
                    SurvivorPrompt(id: "ring", ask: "Name a player with a championship ring",
                                   predicate: awardAtLeast(.careerRings, 1)),
                    SurvivorPrompt(id: "mvp", ask: "Name an MVP winner",
                                   predicate: awardAtLeast(.careerMvp, 1)),
                    SurvivorPrompt(id: "allstar", ask: "Name a multi-time All-Star (3+)",
                                   predicate: awardAtLeast(.careerAllStar, 3)),
                    SurvivorPrompt(id: "dec-1990", ask: "Name a player from the 1990s",
                                   predicate: decadeIs(1990)),
                    SurvivorPrompt(id: "dec-2000", ask: "Name a player from the 2000s",
                                   predicate: decadeIs(2000)),
                    SurvivorPrompt(id: "dec-2010", ask: "Name a player from the 2010s",
                                   predicate: decadeIs(2010)),
                    SurvivorPrompt(id: "fam-big", ask: "Name a Big",
                                   predicate: positionIs("BIG")),
                    SurvivorPrompt(id: "fam-guard", ask: "Name a Guard",
                                   predicate: positionIs("GUARD")),
                ],
                lives: 2))
    }
}
