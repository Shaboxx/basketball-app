import SwiftUI

/// Live gameplay for a GUESS game (Phase 5). Reveals a seeded ordered clue
/// sequence about a mystery player-(season); the player names them via a
/// `.searchable` picker over the pool (Sol Q2c). Fewer clues used before a correct
/// guess = more points. Follows CompareView's launch protocol for the current
/// pool and HistoricalRosterDraftView's for the historical pool.
struct GuessView: View {
    @EnvironmentObject var playersVM: PlayersViewModel
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: GuessDefinition
    var seed: UInt64? = nil

    @State private var store: GuessStore?
    @State private var launchFailed = false

    private var isHistorical: Bool {
        if case .historical = definition.poolSource { return true }
        return false
    }

    var body: some View {
        Group {
            if let store {
                GuessContent(store: store)
            } else if launchFailed {
                ContentUnavailableView("Can't start this game",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Not enough players to build a puzzle."))
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
            let state = try GuessEngine.initialize(
                definition: definition, pool: pool,
                seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = GuessStore(state: state)
        } catch {
            launchFailed = true
        }
    }
}

private struct GuessContent: View {
    @ObservedObject var store: GuessStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @State private var query = ""

    private var teamNames: [String: String] {
        Dictionary(teamsVM.teams.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
    private func teamLabel(_ id: String) -> String { teamNames[id] ?? id }

    /// Answer set filtered by the search query (matches name or season label).
    private var filtered: [GameEntityRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }   // don't dump 14.5k rows until searched
        return store.state.pool.filter {
            $0.name.lowercased().contains(q) ||
            ($0.seasonLabel?.lowercased().contains(q) ?? false)
        }.prefix(50).map { $0 }
    }

    var body: some View {
        content
            .alert("No more clues",
                   isPresented: Binding(get: { store.lastError == .noMoreClues },
                                        set: { if !$0 { store.clearError() } })) {
                Button("OK", role: .cancel) { store.clearError() }
            } message: { Text("Every clue is already revealed — take your guess.") }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .finished(let score):
            finished(score: score)
        case .guessing:
            guessing
        }
    }

    private var guessing: some View {
        List {
            Section("Clues (\(store.state.revealedCount)/\(store.state.orderedClues.count))") {
                ForEach(store.state.revealedClues, id: \.text) { clue in
                    Text(clue.text)
                }
                if store.state.revealedCount < store.state.orderedClues.count {
                    Button {
                        store.revealClue()
                    } label: {
                        Label("Reveal another clue", systemImage: "eye.fill")
                    }
                }
            }
            Section("Your guess") {
                if filtered.isEmpty {
                    Text(query.isEmpty ? "Search for a player to guess."
                                       : "No players match \"\(query)\".")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { e in
                        Button {
                            store.guess(subjectId: e.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(e.name)
                                Text(seasonTeamLabel(e))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search for a player")
    }

    /// Disambiguating subtitle: season + team when present (14.5k dup names).
    private func seasonTeamLabel(_ e: GameEntityRecord) -> String {
        if let s = e.seasonLabel { return "\(s) · \(teamLabel(e.team))" }
        return teamLabel(e.team)
    }

    @ViewBuilder
    private func finished(score: Int) -> some View {
        let won = store.state.status == .won
        VStack(spacing: 12) {
            Image(systemName: won ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(won ? .green : .secondary)
            Text(won ? "Correct!" : "Out of guesses")
                .font(.title2.bold())
            if let target = store.state.target {
                Text(target.name).font(.largeTitle.bold())
                Text(seasonTeamLabel(target))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Score: \(score)").font(.headline).foregroundStyle(.tint)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
