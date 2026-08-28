import SwiftUI

/// Progressive custom-game creator (spec §27). Recombines ONLY the bounded
/// CreatorOptions menus, so every draft it can produce is a legal Definition the
/// engines already run. A persistent footer shows live validator status
/// (feasible / why-not) so the user can't save an impossible game.
struct GameCreatorView: View {
    @EnvironmentObject var creatorStore: GameCreatorStore
    @EnvironmentObject var playersVM: PlayersViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            familySection
            switch creatorStore.draft.family {
            case .roster:         rosterSections
            case .bracket:        bracketSections
            case .compare:        compareSection
            case .classification: classificationSection
            }
            nameSection
            saveSection
        }
        .navigationTitle("Create a Game")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { validationFooter }
    }

    // MARK: - Step 1: family

    private var familySection: some View {
        Section("Game Type") {
            Picker("Type", selection: $creatorStore.draft.family) {
                ForEach(CreatorOptions.EngineFamily.allCases) { fam in
                    Text(fam.displayName).tag(fam)
                }
            }
        }
    }

    // MARK: - Roster

    @ViewBuilder
    private var rosterSections: some View {
        Section("Roster") {
            Picker("Shape", selection: $creatorStore.draft.rosterShape) {
                ForEach(CreatorOptions.rosterShapes) { Text($0.displayName).tag($0) }
            }
            Picker("Picking", selection: $creatorStore.draft.selection) {
                ForEach(CreatorOptions.selectionMethods, id: \.self) {
                    Text($0 == .snake ? "Snake" : "Free Pick").tag($0)
                }
            }
        }
        Section("Scoring & Budget") {
            Picker("Scoring", selection: $creatorStore.draft.rosterScoring) {
                Text("Team Rating").tag(ScoringMethod.teamRating)
                Text("No Winner").tag(ScoringMethod.none)
            }
            Picker("Budget", selection: $creatorStore.draft.economy) {
                ForEach(CreatorOptions.EconomyPreset.allCases) { Text($0.displayName).tag($0) }
            }
        }
        poolFilterSection
    }

    // MARK: - Bracket

    @ViewBuilder
    private var bracketSections: some View {
        Section("Bracket") {
            Picker("Field Size", selection: $creatorStore.draft.bracketFieldSize) {
                ForEach(CreatorOptions.bracketFieldSizes, id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("Seed by rating", isOn: $creatorStore.draft.bracketSeedByRating)
            Picker("Scoring", selection: $creatorStore.draft.bracketScoring) {
                Text("Just for fun").tag(BracketScoring.none)
                Text("Model agreement").tag(BracketScoring.modelAgreement)
            }
        }
        poolFilterSection
    }

    // MARK: - Compare

    private var compareSection: some View {
        Section("Higher or Lower") {
            Picker("Metric", selection: $creatorStore.draft.compareMetric) {
                ForEach(CreatorOptions.compareMetrics, id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            Picker("Direction", selection: $creatorStore.draft.compareDirection) {
                Text("Higher wins").tag(CompareDirection.higher)
                Text("Lower wins").tag(CompareDirection.lower)
            }
        }
    }

    // MARK: - Classification

    private var classificationSection: some View {
        Section("Ranking / Tiers") {
            Picker("Mode", selection: $creatorStore.draft.classificationMode) {
                Text("Total Order").tag(ClassificationMode.totalOrder)
                Text("Tiers (S–D)").tag(ClassificationMode.tiers)
                Text("Start/Bench/Cut").tag(ClassificationMode.uniqueLabels)
            }
            if creatorStore.draft.classificationMode != .uniqueLabels {
                Stepper("Players: \(creatorStore.draft.classificationSubjects)",
                        value: $creatorStore.draft.classificationSubjects, in: 3...20)
            }
        }
    }

    // MARK: - Pool filters (roster + bracket)

    private var poolFilterSection: some View {
        Section {
            ForEach(CreatorOptions.poolFilters) { filter in
                let on = creatorStore.draft.poolFilters.contains(filter)
                Button {
                    if on { creatorStore.draft.poolFilters.removeAll { $0 == filter } }
                    else { creatorStore.draft.poolFilters.append(filter) }
                } label: {
                    HStack {
                        Text(filter.displayName)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Pool Filters")
        } footer: {
            Text("Optional. Restrict which players are eligible.")
        }
    }

    // MARK: - Name + save

    private var nameSection: some View {
        Section("Name") {
            TextField("Game name", text: $creatorStore.draft.title)
        }
    }

    private var saveSection: some View {
        Section {
            Button("Save Game") {
                // Validate + persist against the LIVE pool (the view owns the
                // PlayersViewModel-derived pool; the store's own provider is a
                // fallback). Only dismiss on a successful save.
                if saveAgainstLivePool() { dismiss() }
            }
            .disabled(creatorStore.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Footer

    private var validationFooter: some View {
        // Re-evaluate against the live pool on each render (cheap: bounded roster).
        let error = liveValidation()
        return HStack(spacing: 8) {
            Image(systemName: error == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == nil ? .green : .orange)
            Text(error == nil ? "Ready to play" : message(for: error!))
                .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
    }

    private var livePool: [GameEntityRecord] { GamePoolBuilder.pool(from: playersVM.players) }

    private func liveValidation() -> GameDefinitionValidator.ValidationError? {
        switch GameDefinitionValidator.validate(creatorStore.assembleDraft(), pool: livePool) {
        case .success: return nil
        case .failure(let e): return e
        }
    }

    /// Validate against the live pool and persist on success. Records the failure
    /// on the store so the footer/error surface stays consistent.
    private func saveAgainstLivePool() -> Bool {
        let assembled = creatorStore.assembleDraft()
        switch GameDefinitionValidator.validate(assembled, pool: livePool) {
        case .success:
            creatorStore.persistValidated(assembled)
            return true
        case .failure(let e):
            creatorStore.setValidationError(e)
            return false
        }
    }

    private func message(for e: GameDefinitionValidator.ValidationError) -> String {
        switch e {
        case .emptyPool:            return "No players match these filters"
        case .emptyTitle:           return "Give your game a name"
        case .infeasibleDefinition: return "Not enough players to fill this roster"
        case .incoherentModifiers:  return "These settings conflict"
        case .degenerateScoring:    return "Not enough players for this format"
        case .invalidConfig:        return "Adjust the settings"
        }
    }
}
