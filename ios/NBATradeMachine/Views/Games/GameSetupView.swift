import SwiftUI

/// Shared setup screen for a playable game: participant counts + play mode,
/// bounded by the game's `SetupCapabilities` and persisted per game via
/// `GameSetupStore`. Start pushes the placeholder destination. Coming-Soon /
/// out-of-window games never reach this screen (the hub doesn't navigate to them).
struct GameSetupView: View {
    @EnvironmentObject var setupStore: GameSetupStore
    // Phase-4.5: re-injected below onto the historical launch view (this view's
    // own navigationDestination is a further nav level that won't inherit env).
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let game: DraftGame

    @State private var humans: Int = GameSetupSettings.default.humanCount
    @State private var cpus: Int = GameSetupSettings.default.cpuCount
    @State private var playMode: PlayMode = GameSetupSettings.default.playMode
    @State private var started = false

    private var caps: SetupCapabilities { game.capabilities }

    /// Play modes this game actually offers (F5: local + solo-vs-CPU only).
    private var availableModes: [PlayMode] {
        var modes: [PlayMode] = []
        if caps.allowsLocalFriends { modes.append(.localFriends) }
        if caps.allowsCPU { modes.append(.soloVsCPU) }
        return modes.isEmpty ? [.localFriends] : modes
    }

    var body: some View {
        Form {
            Section {
                Stepper("Players: \(humans)", value: $humans,
                        in: caps.minHumans...caps.effectiveCap)
                    .onChange(of: humans) { _, _ in reclamp() }
                if caps.allowsCPU {
                    Stepper("CPUs: \(cpus)", value: $cpus,
                            in: 0...max(0, caps.effectiveCap - humans))
                        .onChange(of: cpus) { _, _ in reclamp() }
                }
            } header: {
                Text("Participants")
            } footer: {
                Text("Up to \(caps.effectiveCap) total (players + CPUs).")
            }

            if availableModes.count > 1 {
                Section("Play Mode") {
                    Picker("Play Mode", selection: $playMode) {
                        ForEach(availableModes) { Text($0.displayName).tag($0) }
                    }
                }
            }

            Section {
                Button("Start") {
                    persist()
                    started = true
                }
            }
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $started) {
            let settings = GameSetupSettings(humanCount: humans, cpuCount: cpus,
                                             playMode: playMode)
            switch GameLauncher.resolve(game.id) {
            case .roster(let def):
                // Phase-4.5: a historical pool source routes to the historical
                // launch view (sources the bundled dataset); .current keeps the
                // existing live-players path. Engine path is identical for both.
                switch def.poolSource {
                case .current:
                    RosterDraftView(definition: def, settings: settings)
                case .historical:
                    HistoricalRosterDraftView(definition: def, settings: settings)
                        .environmentObject(historicalStore)
                }
            case .classification(let def):
                ClassificationView(definition: def)
            case .compare(let def):
                CompareView(definition: def)
            case .bracket(let def):
                BracketView(definition: def)
            case .guess(let def):
                // Re-inject historicalStore for the historical pool source (this nav
                // level won't inherit the env). Harmless for .current presets.
                GuessView(definition: def)
                    .environmentObject(historicalStore)
            case .quiz(let def):
                QuizView(definition: def)
                    .environmentObject(historicalStore)
            case .survivor(let def):
                SurvivorView(definition: def)
                    .environmentObject(historicalStore)
            case .none:
                GamePlaceholderView(game: game, settings: settings)
            }
        }
        .onAppear(perform: restore)
    }

    private func restore() {
        let s = setupStore.settings(for: game.id, capabilities: caps)
        humans = s.humanCount
        cpus = s.cpuCount
        playMode = availableModes.contains(s.playMode) ? s.playMode : availableModes[0]
    }

    private func reclamp() {
        let c = caps.clamp(humans: humans, cpus: cpus)
        humans = c.humans
        cpus = c.cpus
    }

    private func persist() {
        reclamp()
        setupStore.save(GameSetupSettings(humanCount: humans, cpuCount: cpus, playMode: playMode),
                        for: game.id, capabilities: caps)
    }
}

#Preview {
    NavigationStack {
        GameSetupView(game: DraftGameRegistry.all[0])
            .environmentObject(GameSetupStore())
            .environmentObject(HistoricalPoolStore())
    }
}
