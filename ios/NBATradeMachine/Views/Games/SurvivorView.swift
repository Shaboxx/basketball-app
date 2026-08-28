import SwiftUI

/// Live gameplay for a SURVIVOR game (Phase 5). Renders the current elimination
/// prompt + streak/lives; the player names an entity via a `.searchable` picker
/// over the eligible pool (Sol Q2c), with already-used entities greyed. Follows
/// CompareView's launch protocol (current) / HistoricalRosterDraftView's
/// (historical), branching on `poolSource`.
struct SurvivorView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: SurvivorDefinition
    var seed: UInt64? = nil

    @State private var store: SurvivorStore?
    @State private var launchFailed = false

    private var isHistorical: Bool {
        if case .historical = definition.poolSource { return true }
        return false
    }

    var body: some View {
        Group {
            if let store {
                SurvivorContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Not enough players for these prompts."))
            } else if isHistorical, historicalStore.phase == .failed {
                ContentUnavailableView {
                    Label("Couldn't load historical players", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The historical dataset failed to load.")
                } actions: {
                    Button("Try Again") { Task { await historicalStore.load() } }
                }
            } else {
                ProgressView("Loading players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if isHistorical { await historicalStore.load() } }
        .onAppear(perform: launchIfReady)
        .onReceive(playersVM.$players) { _ in if !isHistorical { launchIfReady() } }
        .onChange(of: historicalStore.phase) { _, newPhase in
            if isHistorical, newPhase == .loaded { launchIfReady() }
        }
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed else { return }
        let pool: [GameEntityRecord]
        switch definition.poolSource {
        case .current:
            if playersVM.players.isEmpty {
                // Still loading: keep spinning. Loaded-but-empty: latch failure.
                if playersVM.hasLoaded { launchFailed = true }
                return
            }
            pool = GamePoolBuilder.pool(from: playersVM.players)
            // A built-but-empty pool is a terminal config failure when the roster is done.
            if pool.isEmpty {
                if playersVM.hasLoaded { launchFailed = true }
                return
            }
        case .historical(let filter):
            guard historicalStore.phase == .loaded else { return }
            pool = historicalStore.pool(for: filter)
        }
        // Historical loaded-but-empty pool is a terminal config failure (latch, don't spin).
        guard !pool.isEmpty else { launchFailed = true; return }
        do {
            let state = try SurvivorEngine.initialize(
                definition: definition, pool: pool,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = SurvivorStore(state: state)
        } catch {
            launchFailed = true
        }
    }
}

private struct SurvivorContent: View {
    @ObservedObject var store: SurvivorStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var query = ""

    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }

    private var filtered: [GameEntityRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return store.state.pool.filter {
            $0.name.lowercased().contains(q) ||
            ($0.seasonLabel?.lowercased().contains(q) ?? false)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        content
            .alert("Not allowed",
                   isPresented: Binding(get: { store.lastError != nil },
                                        set: { if !$0 { store.clearError() } })) {
                Button("OK", role: .cancel) { store.clearError() }
            } message: { Text(errorText(store.lastError)) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let streak):
            finished(streak: streak)
        case .playing:
            playing
        }
    }

    private var playing: some View {
        List {
            Section {
                if let prompt = store.state.currentPrompt {
                    Text(prompt.ask).font(.title3.bold())
                }
                HStack {
                    Label("Streak \(store.state.streak)", systemImage: "flame.fill")
                    Spacer()
                    Label("Lives \(store.state.livesRemaining)", systemImage: "heart.fill")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your answer") {
                if filtered.isEmpty {
                    Text(query.isEmpty ? "Search for a player to name."
                                       : "No players match \"\(query)\".")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { e in
                        let used = store.state.usedIds.contains(e.id)
                        Button {
                            store.submit(subjectId: e.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(e.name)
                                Text(seasonTeamLabel(e))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(used)
                        .opacity(used ? 0.4 : 1)
                    }
                }
            }
            Section {
                Button(role: .destructive) { store.skip() } label: {
                    Label("Skip (costs a life)", systemImage: "forward.fill")
                }
            }
        }
        .searchable(text: $query, prompt: "Search for a player")
    }

    private func seasonTeamLabel(_ e: GameEntityRecord) -> String {
        if let s = e.seasonLabel { return "\(s) · \(teamLabel(e.team))" }
        return teamLabel(e.team)
    }

    private func finished(streak: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "flame.fill").font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Streak: \(streak)").font(.largeTitle.bold())
            Text("Game over").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorText(_ e: SurvivorError?) -> String {
        switch e {
        case .alreadyUsed:    return "You already named that player — no repeats."
        case .doesNotSatisfy: return "That player doesn't fit the prompt."
        default:              return "That answer isn't allowed."
        }
    }
}
