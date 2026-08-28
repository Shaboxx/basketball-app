import Foundation
import SwiftUI
import Combine

/// Drives the custom-game creator wizard AND owns the "My Games" list. Injected
/// app-wide at the ContentView root (like GameSetupStore). The pool is supplied
/// lazily by a closure (`poolProvider`) so the store never holds a
/// PlayersViewModel; the view passes `GamePoolBuilder.pool(from:)`.
@MainActor
final class GameCreatorStore: ObservableObject {

    /// The wizard's in-progress selections (bounded menu picks). The store
    /// assembles these into a `GameDraft` on demand.
    struct Draft: Equatable {
        var family: CreatorOptions.EngineFamily = .roster
        var title: String = ""
        // roster
        var rosterShape: CreatorOptions.RosterShape = .flexFive
        var selection: SelectionMethod = .freePick
        var rosterScoring: ScoringMethod = .teamRating
        var economy: CreatorOptions.EconomyPreset = .noBudget
        var poolFilters: [CreatorOptions.PoolFilter] = []
        // bracket
        var bracketFieldSize: Int = 8
        var bracketScoring: BracketScoring = .modelAgreement
        var bracketSeedByRating: Bool = true
        // compare
        var compareMetric: CompareMetric = .overall
        var compareDirection: CompareDirection = .higher
        // classification
        var classificationMode: ClassificationMode = .totalOrder
        var classificationSubjects: Int = 8
    }

    @Published var draft = Draft()
    @Published var step: Int = 0
    @Published private(set) var myGames: [GameDraft] = []
    @Published private(set) var validationError: GameDefinitionValidator.ValidationError?

    private let repository: GameDefinitionRepository
    private let poolProvider: () -> [GameEntityRecord]

    init(repository: GameDefinitionRepository = LocalGameDefinitionRepository(),
         poolProvider: @escaping () -> [GameEntityRecord] = { [] }) {
        self.repository = repository
        self.poolProvider = poolProvider
        self.myGames = repository.load()
    }

    nonisolated deinit {}

    // MARK: - My Games

    func reload() { myGames = repository.load() }

    func delete(id: String) {
        repository.delete(id: id)
        reload()
    }

    // MARK: - Wizard

    func resetWizard() {
        draft = Draft()
        step = 0
        validationError = nil
    }

    /// Assemble the current wizard selections into a persistable `GameDraft`. Uses
    /// a stable-per-save uuid string as the definition id.
    func assembleDraft() -> GameDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defId = "custom-" + UUID().uuidString.prefix(8)
        let payload: GameDraft.Payload
        switch draft.family {
        case .roster:
            let entityConstraints = draft.poolFilters.compactMap(\.entityConstraint)
            let rosterConstraints = draft.poolFilters.compactMap(\.rosterConstraint)
            let def = GameDefinition(
                id: String(defId), title: title, engineType: .rosterConstruction,
                entityConstraints: entityConstraints,
                rosterConstraints: rosterConstraints,
                roster: draft.rosterShape.config,
                selection: SelectionConfig(method: draft.selection,
                                           sharedPool: draft.selection == .snake,
                                           offeringsPerTurn: nil),
                scoring: draft.rosterScoring,
                economy: draft.economy.config)
            payload = .roster(def)
        case .bracket:
            let entityConstraints = draft.poolFilters.compactMap(\.entityConstraint)
            let def = BracketDefinition(id: String(defId), title: title,
                                        fieldSize: draft.bracketFieldSize,
                                        seedByRating: draft.bracketSeedByRating,
                                        entityConstraints: entityConstraints,
                                        scoring: draft.bracketScoring)
            payload = .bracket(def)
        case .compare:
            let def = CompareDefinition(id: String(defId), title: title,
                                        config: CompareConfig(metric: draft.compareMetric,
                                                              direction: draft.compareDirection))
            payload = .compare(def)
        case .classification:
            let labels: [String]
            switch draft.classificationMode {
            case .totalOrder:  labels = []
            case .tiers:       labels = ["S", "A", "B", "C", "D"]
            case .uniqueLabels: labels = ["START", "BENCH", "CUT"]
            }
            let subjects = draft.classificationMode == .uniqueLabels
                ? labels.count : draft.classificationSubjects
            let def = ClassificationDefinition(id: String(defId), title: title,
                config: ClassificationConfig(mode: draft.classificationMode, labels: labels,
                                             subjectCount: subjects, candidatePoolSize: 60))
            payload = .classification(def)
        }
        return GameDraft(title: title, payload: payload)
    }

    /// Live feasibility of the current wizard selections against the live pool.
    /// Returns nil on success; a ValidationError otherwise (drives the footer).
    func currentValidation() -> GameDefinitionValidator.ValidationError? {
        let assembled = assembleDraft()
        switch GameDefinitionValidator.validate(assembled, pool: poolProvider()) {
        case .success: return nil
        case .failure(let e): return e
        }
    }

    /// Validate the wizard against the injected pool provider and, only on
    /// success, persist it. Returns true when saved. Blocks the save on any
    /// validation failure (spec §28 — the validator is the hard gate). Used when
    /// the store's own `poolProvider` is the source of truth (e.g. tests).
    @discardableResult
    func validateAndSave() -> Bool {
        let assembled = assembleDraft()
        switch GameDefinitionValidator.validate(assembled, pool: poolProvider()) {
        case .success:
            persistValidated(assembled)
            return true
        case .failure(let e):
            setValidationError(e)
            return false
        }
    }

    /// Persist an already-validated draft (the caller validated against the LIVE
    /// pool it owns) and refresh the My-Games list. Clears any prior error.
    func persistValidated(_ draft: GameDraft) {
        repository.save(draft)
        reload()
        validationError = nil
    }

    /// Surface a validation failure (the caller's own live-pool validation failed).
    func setValidationError(_ e: GameDefinitionValidator.ValidationError) {
        validationError = e
    }
}
