import Foundation

/// One SURVIVOR elimination prompt: a human-readable ask plus the `GameConstraint`
/// predicate an answer must satisfy. The predicate reuses the existing
/// `GameConstraintEvaluator` (single-entity scope) so prompt semantics match the
/// rest of the engine exactly.
///
/// ⚠️ Position prompts on the HISTORICAL pool must be phrased over the collapsed
/// families (GUARD/WING/BIG), NOT the 5-code position — the historical position
/// string IS the family, so a "name a Center" ask would never match. Current-pool
/// prompts may use the 5-code position.
nonisolated struct SurvivorPrompt: Codable, Equatable, Identifiable {
    let id: String              // stable key for the prompt (for tests / dedup)
    let ask: String             // "Name a player with a championship ring"
    let predicate: GameConstraint

    init(id: String, ask: String, predicate: GameConstraint) {
        self.id = id
        self.ask = ask
        self.predicate = predicate
    }

    /// Does an entity satisfy this prompt's predicate?
    func matches(_ e: GameEntityRecord) -> Bool {
        GameConstraintEvaluator.satisfies(e, predicate)
    }
}

/// A SURVIVOR game's configuration. A seeded sequence of prompts is drawn from
/// `prompts` (cycled/reshuffled as needed); each answered correctly extends the
/// streak. `lives` wrong/invalid answers end the game.
nonisolated struct SurvivorConfig: Codable, Equatable {
    let prompts: [SurvivorPrompt]
    let lives: Int

    init(prompts: [SurvivorPrompt], lives: Int) {
        self.prompts = prompts
        self.lives = lives
    }
}

/// A SURVIVOR game (self-contained; NOT the roster `GameDefinition`).
nonisolated struct SurvivorDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let poolSource: GamePoolSource
    let config: SurvivorConfig

    init(id: String, title: String, poolSource: GamePoolSource, config: SurvivorConfig) {
        self.id = id
        self.title = title
        self.poolSource = poolSource
        self.config = config
    }
}
