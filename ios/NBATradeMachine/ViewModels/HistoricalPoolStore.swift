import Foundation
import Combine

/// The historical-dataset load phase. Top-level (NOT nested in the @MainActor
/// store) so it stays cleanly off the MainActor and is usable in nonisolated
/// tests. Mirrors `FantasyPhase`.
nonisolated enum HistoricalPhase: Equatable { case idle, loading, loaded, failed }

/// Loads the bundled `game-players-historical.json` (~12MB, 14569 player-season
/// records) ONCE, decoding OFF the main actor, then publishes the decoded
/// dataset on the main actor. Injected app-wide at the ContentView root like the
/// other load-once stores; `HistoricalRosterDraftView` reads it.
///
/// Load-once with retry: a failed decode leaves `.failed`, and `load()` retries
/// from `.failed`/`.idle` — the same idempotent shape as the other stores, so a
/// view's `onAppear` + `$phase` re-fire is a safe no-op once loaded.
@MainActor
final class HistoricalPoolStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → task-local double-free under XCTest).
    nonisolated deinit {}

    @Published private(set) var dataset: HistoricalDataset?
    @Published private(set) var phase: HistoricalPhase = .idle

    /// Phase-6: the DISTINCT-player collapse (one per nbaPlayerId), computed ONCE
    /// off-main from the same 12MB decode — NOT a second decode. Shared answer
    /// space for GRID + CONNECTION. nil until the dataset loads.
    @Published private(set) var distinctPlayers: [HistoricalPlayerEntity] = []

    /// Phase-6: the teammate adjacency graph (~10MB `teammate-graph.json`), decoded
    /// ONCE off-main. Has its OWN phase so a graph failure doesn't sink the season
    /// pool (Phase 4.5/5 don't need the graph). nil until `loadGraph` succeeds.
    @Published private(set) var graph: TeammateGraph?
    @Published private(set) var graphPhase: HistoricalPhase = .idle

    /// The bundle resource name (without extension). Injectable so tests can point
    /// at a small fixture bundle if needed; production uses the shipped 12MB file.
    private let resourceName: String
    /// Phase-6 teammate-graph resource name (bundled at 10MB by Phase 4.5).
    private let graphResourceName: String
    private let bundle: Bundle

    init(resourceName: String = "game-players-historical",
         graphResourceName: String = "teammate-graph",
         bundle: Bundle = .main) {
        self.resourceName = resourceName
        self.graphResourceName = graphResourceName
        self.bundle = bundle
    }

    /// Decode-once (with retry on failure). The heavy `JSONDecoder` work runs on
    /// a detached task (off the main actor); only the small phase/dataset publish
    /// happens back on the main actor, so the first historical-card open never
    /// stalls the UI.
    func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        let name = resourceName
        let bundle = self.bundle
        // Decode the 12MB dataset AND compute the distinct-player collapse on the
        // SAME detached decode (one 12MB decode, not two) — return both so GRID/
        // CONNECTION never re-decode. Sendable value types cross the actor safely.
        let result: (HistoricalDataset, [HistoricalPlayerEntity])? =
            await Task.detached(priority: .userInitiated) {
                guard let ds = Self.decode(resourceName: name, bundle: bundle) else { return nil }
                let distinct = HistoricalPoolBuilder.loadDistinctPlayers(from: ds)
                return (ds, distinct)
            }.value
        if let result {
            dataset = result.0
            distinctPlayers = result.1
            phase = .loaded
        } else {
            phase = .failed
        }
    }

    /// Load-once (with retry) decode of the ~10MB teammate graph, OFF the main
    /// actor. Separate from `load()` so a graph failure doesn't sink the season
    /// pool. GRID/CONNECTION views call this in addition to `load()`.
    func loadGraph() async {
        guard graphPhase == .idle || graphPhase == .failed else { return }
        graphPhase = .loading
        let name = graphResourceName
        let bundle = self.bundle
        let decoded: TeammateGraph? = await Task.detached(priority: .userInitiated) {
            Self.decodeGraph(resourceName: name, bundle: bundle)
        }.value
        if let decoded {
            graph = decoded
            graphPhase = .loaded
        } else {
            graphPhase = .failed
        }
    }

    /// Off-main graph decode helper. `nonisolated static` so it runs on the
    /// detached task's executor. Returns nil on a missing resource or decode error.
    nonisolated static func decodeGraph(resourceName: String, bundle: Bundle) -> TeammateGraph? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? TeammateGraph.load(from: data)
    }

    /// Off-main decode helper. `nonisolated static` so it runs on the detached
    /// task's executor, not the main actor. Returns nil on a missing resource or
    /// a decode error (the caller surfaces `.failed`).
    nonisolated static func decode(resourceName: String, bundle: Bundle) -> HistoricalDataset? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HistoricalDataset.self, from: data)
    }

    /// Build the frozen pool for a historical `GameDefinition`. Returns `[]` when
    /// the dataset isn't loaded yet or the definition isn't a historical one
    /// (`.current` pool source) — the caller shows a ProgressView / retries until
    /// `.loaded`. The definition's `entityConstraints` still run in the engine's
    /// `initialize` afterward (authoritative gate); this only applies the cheap
    /// `HistoricalFilter` prefilter.
    func pool(for definition: GameDefinition) -> [GameEntityRecord] {
        guard let dataset else { return [] }
        guard case .historical(let filter) = definition.poolSource else { return [] }
        return HistoricalPoolBuilder.pool(from: dataset, filter: filter)
    }

    /// Direct filter access (used by tests and any non-definition caller).
    func pool(for filter: HistoricalFilter) -> [GameEntityRecord] {
        guard let dataset else { return [] }
        return HistoricalPoolBuilder.pool(from: dataset, filter: filter)
    }
}
