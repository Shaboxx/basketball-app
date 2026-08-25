import Foundation

/// Resolves a hub card id to the engine + definition its Start button launches.
/// Pure + testable — the setup view just switches on the result. (R13)
nonisolated enum GameLaunch: Equatable {
    case roster(GameDefinition)
    case classification(ClassificationDefinition)
    case compare(CompareDefinition)
    case none
}

nonisolated enum GameLauncher {
    static func resolve(_ id: String) -> GameLaunch {
        if let d = GamePresets.definition(for: id) { return .roster(d) }
        if let d = ClassificationPresets.definition(for: id) { return .classification(d) }
        if let d = ComparePresets.definition(for: id) { return .compare(d) }
        return .none
    }
}
