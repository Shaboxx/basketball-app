import SwiftUI

/// Live gameplay for a ROSTER_CONSTRUCTION definition whose pool comes from the
/// bundled HISTORICAL dataset (Phase-4.5). Mirrors `RosterDraftView`'s launch
/// protocol exactly, but sources the pool from the app-wide `HistoricalPoolStore`
/// (off-main load-once) instead of `PlayersViewModel`. Once the pool is built it
/// hands the session to the SAME `GameSessionStore` + `RosterDraftContent`, so
/// the engine / evaluator / feasibility / CPU / gameplay UI are all unchanged.
struct HistoricalRosterDraftView: View {
    @EnvironmentObject var historicalStore: HistoricalPoolStore
    let definition: GameDefinition
    let settings: GameSetupSettings
    /// Canonical shared-challenge seed (Sol fix 1); nil for preset/creator callers.
    var seed: UInt64? = nil

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
            } else if historicalStore.phase == .failed {
                ContentUnavailableView {
                    Label("Couldn't load historical players",
                          systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The historical dataset failed to load.")
                } actions: {
                    Button("Try Again") { Task { await historicalStore.load() } }
                }
            } else {
                ProgressView("Loading historical players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(definition.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await historicalStore.load() }
        .onAppear(perform: launchIfReady)
        // Launch as soon as the store reaches `.loaded`. MUST use `onChange` (fires
        // AFTER the stored `phase` updates), NOT `onReceive($phase)` — @Published
        // emits during `willSet`, so an onReceive handler that re-reads the stored
        // `phase` would see the OLD value and never launch on first load (the store
        // is lazily loaded under this view, so it transitions idle→loading→loaded
        // live). The `store == nil` guard keeps it a no-op after the first launch.
        .onChange(of: historicalStore.phase) { _, newPhase in
            if newPhase == .loaded { launchIfReady() }
        }
    }

    private func launchIfReady() {
        guard store == nil, !launchFailed, historicalStore.phase == .loaded else { return }
        let pool = historicalStore.pool(for: definition)
        // A loaded-but-empty pool means the dataset is present but this
        // definition's source is `.current` or the filter matched nothing — treat
        // as a launch failure rather than initializing an empty game.
        guard !pool.isEmpty else { launchFailed = true; return }
        let participants = GameSessionStore.participants(
            humans: settings.humanCount, cpus: settings.cpuCount)
        do {
            let state = try RosterConstructionEngine.initialize(
                definition: definition, participants: participants,
                pool: pool, seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max))
            store = GameSessionStore(state: state)
        } catch {
            launchFailed = true
        }
    }
}
