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

    /// The bundle resource name (without extension). Injectable so tests can point
    /// at a small fixture bundle if needed; production uses the shipped 12MB file.
    private let resourceName: String
    private let bundle: Bundle

    init(resourceName: String = "game-players-historical", bundle: Bundle = .main) {
        self.resourceName = resourceName
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
        let decoded: HistoricalDataset? = await Task.detached(priority: .userInitiated) {
            Self.decode(resourceName: name, bundle: bundle)
        }.value
        if let decoded {
            dataset = decoded
            phase = .loaded
        } else {
            phase = .failed
        }
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
