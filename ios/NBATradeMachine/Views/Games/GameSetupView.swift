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
    // Phase 7: re-injected onto OnlineSetupView (a further nav level). Injected
    // app-wide in ContentView (Mock-backed until Firebase is configured), so it's
    // always reachable even though the online path stays dark behind the flag.
    @EnvironmentObject var onlineStore: OnlineGameSessionStore
    // The live-pool roster stores. Re-injected onto the current-pool RosterDraftView
    // below (this view's navigationDestination is a further nav level that won't
    // inherit env). GamesHubView injects both onto this view, so reading them is safe.
    @EnvironmentObject var playersVM: PlayersViewModel
    @EnvironmentObject var teamsVM: TeamsViewModel
    let game: DraftGame

    @State private var humans: Int = GameSetupSettings.default.humanCount
    @State private var cpus: Int = GameSetupSettings.default.cpuCount
    @State private var playMode: PlayMode = GameSetupSettings.default.playMode
    @State private var started = false

    private var caps: SetupCapabilities { game.capabilities }

    /// Play modes this game actually offers. `.online` (Phase 7) appears only when
    /// the game `allowsOnline` AND `AppConfig.onlineGamesEnabled` is on, so it stays
    /// dark until deploy.
    private var availableModes: [PlayMode] {
        var modes: [PlayMode] = []
        if caps.allowsLocalFriends { modes.append(.localFriends) }
        if caps.allowsCPU { modes.append(.soloVsCPU) }
        if caps.allowsOnline && OnlineGamesGate.shouldShow() { modes.append(.online) }
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
            // Every gameplay view is reached through THIS nested navigationDestination,
            // which does NOT inherit the environment. Inject the stores the gameplay
            // views read uniformly — playersVM/teamsVM (live pool: roster/classification/
            // compare/bracket/guess/quiz/survivor) and historicalStore (bundled dataset:
            // historical roster/guess/quiz/survivor/grid/connection). Injecting a store a
            // given view ignores is harmless; a MISSING one crashes at render with
            // "No ObservableObject of type … found".
            gameplayDestination()
                .environmentObject(playersVM)
                .environmentObject(teamsVM)
                .environmentObject(historicalStore)
        }
        .onAppear(perform: restore)
    }

    /// The gameplay view for this game. Kept separate so the shared environment-object
    /// injection (playersVM/teamsVM/historicalStore) is applied once at the call site
    /// above rather than per-branch. onlineStore is injected inline on the online branch.
    @ViewBuilder
    private func gameplayDestination() -> some View {
        let settings = GameSetupSettings(humanCount: humans, cpuCount: cpus, playMode: playMode)
        switch GameLauncher.resolve(game.id) {
        case .roster(let def):
            // Phase 7: an online roster game routes to OnlineSetupView (create / join by
            // code); reachable only when the game allowsOnline AND onlineGamesEnabled
            // (see availableModes), so it stays dark until deploy. Otherwise local.
            if playMode == .online {
                OnlineSetupView(definition: def, settings: settings)
                    .environmentObject(onlineStore)
            } else {
                // Phase-4.5: a historical pool source routes to the historical launch
                // view (bundled dataset); .current keeps the live-players path.
                switch def.poolSource {
                case .current:
                    RosterDraftView(definition: def, settings: settings)
                case .historical:
                    HistoricalRosterDraftView(definition: def, settings: settings)
                }
            }
        case .classification(let def): ClassificationView(definition: def)
        case .compare(let def):        CompareView(definition: def)
        case .bracket(let def):        BracketView(definition: def)
        case .guess(let def):          GuessView(definition: def)
        case .quiz(let def):           QuizView(definition: def)
        case .survivor(let def):       SurvivorView(definition: def)
        case .grid(let def):           GridView(definition: def)
        case .connection(let def):     ConnectionView(definition: def)
        case .none:                    GamePlaceholderView(game: game, settings: settings)
        }
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
            .environmentObject(OnlineGameSessionStore(transport: MockGameSessionTransport()))
    }
}
