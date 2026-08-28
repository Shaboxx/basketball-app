import Foundation

/// Resolves a hub card id to the engine + definition its Start button launches.
/// Pure + testable — the setup view just switches on the result. (R13)
nonisolated enum GameLaunch: Equatable {
    case roster(GameDefinition)
    case classification(ClassificationDefinition)
    case compare(CompareDefinition)
    case bracket(BracketDefinition)     // Phase 8 — new engine
    case none
}

nonisolated enum GameLauncher {
    static func resolve(_ id: String) -> GameLaunch {
        if let d = GamePresets.definition(for: id) { return .roster(d) }
        // Phase-4.5 historical presets flow through the SAME .roster destination
        // (they're roster-construction games with a .historical pool source); the
        // setup view branches on `def.poolSource` to pick the right pool.
        if let d = HistoricalPresets.definition(for: id) { return .roster(d) }
        if let d = ClassificationPresets.definition(for: id) { return .classification(d) }
        if let d = ComparePresets.definition(for: id) { return .compare(d) }
        if let d = BracketPresets.definition(for: id) { return .bracket(d) }
        return .none
    }
}
