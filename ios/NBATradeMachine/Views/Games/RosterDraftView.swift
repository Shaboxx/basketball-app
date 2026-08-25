import SwiftUI

/// Live gameplay for a ROSTER_CONSTRUCTION definition. Builds the pool from the
/// app-wide PlayersViewModel, then hands the session to a per-session
/// GameSessionStore. Solo picks freely; pass-and-play gates each human turn
/// behind a handoff screen; CPU turns advance themselves.
struct RosterDraftView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    let definition: GameDefinition
    let settings: GameSetupSettings

    @State private var store: GameSessionStore?
    @State private var launchFailed = false

    var body: some View {
        Group {
            if let store {
                RosterDraftContent(store: store)
            } else if launchFailed {
                ContentUnavailableView(
                    "Can't start this game",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Not enough eligible players for this setup."))
            } else {
                ProgressView("Loading players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: launchIfReady)
        .onReceive(playersVM.$players) { _ in launchIfReady() }
    }

    private func launchIfReady() {
        // Called from BOTH onAppear and onReceive(players) — both fire on first
        // appearance. The `store == nil` guard + synchronous MainActor assignment
        // make this idempotent, so the second call is a no-op. Assumes
        // PlayersViewModel publishes the full roster atomically (non-empty ⇒
        // complete); a partial list would latch launchFailed and not retry.
        guard store == nil, !launchFailed, !playersVM.players.isEmpty else { return }
        let pool = GamePoolBuilder.pool(from: playersVM.players)
        let participants = GameSessionStore.participants(
            humans: settings.humanCount, cpus: settings.cpuCount)
        do {
            let state = try RosterConstructionEngine.initialize(
                definition: definition, participants: participants,
                pool: pool, seed: UInt64.random(in: UInt64.min...UInt64.max))
            store = GameSessionStore(state: state)
        } catch {
            launchFailed = true
        }
    }
}

/// The session-bound content. Separate struct so the store is non-optional.
private struct RosterDraftContent: View {
    @ObservedObject var store: GameSessionStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var pendingEntity: GameEntityRecord?
    @State private var searchText = ""

    /// teamId → readable name, built once per render (≈30 teams).
    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) },
                   uniquingKeysWith: { first, _ in first })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }

    // MARK: modifier helpers

    private var reveal: RevealConfig? { store.state.definition.reveal }
    private var economy: EconomyConfig? { store.state.definition.economy }

    /// Display name for an OFFERED (unplaced) entity, masked per the reveal config.
    private func maskedName(_ e: GameEntityRecord) -> String {
        (reveal?.masks(.identity) ?? false) ? "???" : e.name
    }
    private func maskedTeam(_ e: GameEntityRecord) -> String {
        (reveal?.masks(.team) ?? false) ? "???" : teamLabel(e.team)
    }
    private func maskedRating(_ e: GameEntityRecord) -> String {
        (reveal?.masks(.rating) ?? false) ? "???" : String(format: "%+.1f", e.rating)
    }
    /// Price label for an entity under the economy, or nil when no economy.
    private func priceLabel(_ e: GameEntityRecord) -> String? {
        guard let econ = economy else { return nil }
        let p = econ.price(e)
        switch econ.pricingMethod {
        case .databaseValue: return "$\(p / 1_000_000)M"
        case .tierPrice:     return "$\(p)"
        }
    }
    private func remainingBudgetLabel(seat: Int) -> String? {
        guard let econ = economy, let rem = store.state.budgets?[seat] else { return nil }
        switch econ.pricingMethod {
        case .databaseValue: return "Budget: $\(rem / 1_000_000)M left"
        case .tierPrice:     return "Budget: $\(rem) left"
        }
    }
    private func rerollsLeft(seat: Int) -> Int {
        store.state.actionInventory?[seat].rerolls ?? 0
    }

    var body: some View {
        switch store.phase {
        case .finished(let result):
            RosterDraftResultView(state: store.state, result: result,
                                  teamLabel: teamLabel)
        case .handoff(let seat):
            handoffScreen(seat: seat)
        case .picking(let seat):
            pickingScreen(seat: seat)
        case .cpuThinking(let seat):
            VStack(spacing: 12) {
                rosterBoard(focusSeat: seat)
                Spacer()
                ProgressView()
                Text("\(store.state.participants[seat].displayName) is picking…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: pieces

    private func handoffScreen(seat: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Pass the device to")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(store.state.participants[seat].displayName)
                .font(.title.bold())
            Button("I'm ready") { store.confirmHandoff() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickingScreen(seat: Int) -> some View {
        let eligible = RosterConstructionEngine.eligibleEntities(store.state, seat: seat)
        let isBlind = reveal?.masks(.identity) ?? false
        let shown = (searchText.isEmpty || isBlind)
            ? eligible
            : eligible.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        // Show the reroll whenever the seat has one and there's a live offering.
        // (An offering-usefulness gate would need the offering-INDEPENDENT legal
        // pool count — eligibleEntities is already offering-filtered, so its
        // count is ≤ offeringsPerTurn and can't express "more picks exist". The
        // full legal pool is large, so a reroll is virtually always useful; the
        // rare 1-legal-pick corner just redraws the same player, harmlessly.)
        return VStack(spacing: 0) {
            rosterBoard(focusSeat: seat)
            if let budget = remainingBudgetLabel(seat: seat) {
                Text(budget)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            if rerollsLeft(seat: seat) > 0 && store.state.offerings != nil {
                Button {
                    store.reroll()
                } label: {
                    Label("Reroll (\(rerollsLeft(seat: seat)) left)",
                          systemImage: "dice.fill")
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            List(shown.sorted { $0.rating > $1.rating }) { entity in
                Button {
                    tap(entity, seat: seat)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(maskedName(entity))
                            Text("\(maskedTeam(entity)) · \(entity.position)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let price = priceLabel(entity) {
                            Text(price)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(maskedRating(entity))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .modifier(ConditionalSearchable(enabled: !isBlind, text: $searchText))
        }
        .confirmationDialog("Choose a slot",
                            isPresented: Binding(get: { pendingEntity != nil },
                                                 set: { if !$0 { pendingEntity = nil } }),
                            titleVisibility: .visible) {
            if let entity = pendingEntity {
                ForEach(RosterConstructionEngine.validSlots(store.state, seat: seat,
                                                            entity: entity)) { slot in
                    Button(slot.label) {
                        store.pick(entityId: entity.id, slotId: slot.id)
                        pendingEntity = nil
                    }
                }
            }
        }
        .alert("Pick not allowed",
               isPresented: Binding(get: { store.lastError != nil },
                                    set: { if !$0 { store.clearError() } })) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(errorText(store.lastError))
        }
    }

    private func tap(_ entity: GameEntityRecord, seat: Int) {
        let slots = RosterConstructionEngine.validSlots(store.state, seat: seat,
                                                        entity: entity)
        if slots.count == 1 {
            store.pick(entityId: entity.id, slotId: slots[0].id)
        } else {
            pendingEntity = entity
        }
    }

    /// Current seat's board: one chip per slot, filled or labeled.
    private func rosterBoard(focusSeat: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.state.participants[focusSeat].displayName)'s roster")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.state.definition.roster.slots) { slot in
                        let filled = store.state.rosters[focusSeat]
                            .first { $0.slotId == slot.id }
                        VStack(spacing: 2) {
                            Text(slot.label).font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(filled?.entity.name ?? "—")
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(filled == nil ? Color.secondary.opacity(0.12)
                                                  : Color.accentColor.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private func errorText(_ error: GameEngineError?) -> String {
        switch error {
        case .entityUnavailable:        return "That player is already taken."
        case .slotFilled:               return "That slot is already filled."
        case .slotRejectsEntity:        return "That player can't fill that slot."
        case .rosterConstraintViolated: return "That pick breaks a roster rule."
        case .notAnOffering:            return "Pick one of the offered players."
        case .cannotAfford:             return "Not enough budget for that player."
        case .noRerollsLeft:            return "No rerolls left."
        case .nothingToReroll:          return "Nothing to reroll right now."
        default:                        return "That pick isn't allowed right now."
        }
    }
}

/// Side-by-side final rosters; scores + winner only when the game scores itself.
private struct RosterDraftResultView: View {
    let state: RosterGameState
    let result: GameResult
    let teamLabel: (String) -> String

    var body: some View {
        List {
            if let winner = result.winnerSeat {
                Section {
                    Label("\(state.participants[winner].displayName) wins!",
                          systemImage: "trophy.fill")
                        .font(.headline)
                }
            }
            ForEach(state.participants) { participant in
                Section {
                    ForEach(result.rosters[participant.id], id: \.slotId) { assignment in
                        HStack {
                            Text(assignment.slotId).font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(assignment.entity.name)
                                Text(teamLabel(assignment.entity.team))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%+.1f", assignment.entity.rating))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(participant.displayName)
                        Spacer()
                        if let scores = result.scores {
                            Text(String(format: "%.1f", scores[participant.id]))
                        }
                    }
                }
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Applies `.searchable` only when enabled — a blind game hides identities so
/// search is meaningless (and would leak names).
private struct ConditionalSearchable: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "Search players")
        } else {
            content
        }
    }
}
