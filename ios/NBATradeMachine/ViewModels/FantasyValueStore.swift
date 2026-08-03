import Foundation
import Combine

/// The app-wide fantasy load phase. Top-level (NOT nested in the @MainActor store)
/// so `FantasyEmptyState.decide` and its test stay cleanly off the MainActor.
nonisolated enum FantasyPhase: Equatable { case idle, loading, loaded, empty, failed }

/// Loads the whole `fantasyValues` collection (+ `_meta`) once and serves per-slug
/// lookups, keyed by canonical (period-stripped) slug. Mirrors `LeagueNormsViewModel`
/// + the `PlayersViewModel.load()` guard (idempotent load-once).
@MainActor
final class FantasyValueStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published private(set) var values: [String: FantasyValue] = [:]
    @Published private(set) var meta: FantasyMeta?
    @Published private(set) var phase: FantasyPhase = .idle

    // SP-5 seasonal (Rdur) value lives on THIS store — not a separate one — because
    // FantasyValueStore is already injected on every path that renders the player page
    // (36 sheet/cover sites; SwiftUI sheets don't inherit environment). A separate
    // @EnvironmentObject would crash on any path that re-injects only this store.
    @Published private(set) var seasonalBySlug: [String: FantasySeasonalValue] = [:]
    @Published private(set) var seasonalMeta: FantasySeasonalMeta?
    @Published private(set) var seasonalPhase: FantasyPhase = .idle

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    /// Loads both collections concurrently; each is independently load-once-with-retry so a
    /// failure/empty in one never blocks the other.
    func load() async {
        async let a: Void = loadValues()
        async let b: Void = loadSeasonal()
        _ = await (a, b)
    }

    private func loadValues() async {
        // Load-once, but allow a RETRY after a failed fetch — with lazy loading the first
        // fetch happens on the user's fantasy-mode toggle, so a transient failure must be
        // recoverable (re-toggle / foreground refresh) without an app relaunch.
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let (vals, m) = try await service.fetchFantasyValues()
            values = vals; meta = m
            phase = vals.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed
        }
    }

    private func loadSeasonal() async {
        guard seasonalPhase == .idle || seasonalPhase == .failed else { return }
        seasonalPhase = .loading
        do {
            let (v, m) = try await service.fetchFantasySeasonal()
            seasonalBySlug = v; seasonalMeta = m
            seasonalPhase = v.isEmpty ? .empty : .loaded
        } catch {
            seasonalPhase = .failed
        }
    }

    func value(for slug: String) -> FantasyValue? { values[Self.canonicalSlug(slug)] }

    /// Per-slug seasonal lookup. Returns nil for an unknown player OR a stale-season straggler
    /// whose `season` disagrees with `seasonalMeta.season` (merge-only rollover guard).
    func seasonalValue(for slug: String) -> FantasySeasonalValue? {
        guard let v = seasonalBySlug[Self.canonicalSlug(slug)] else { return nil }
        if let metaSeason = seasonalMeta?.season, !metaSeason.isEmpty, v.season != metaSeason { return nil }
        return v
    }

    /// Port of the Python `canonical_slug`: strip ".", collapse doubled hyphens, trim
    /// edge hyphens — matches the period-stripped Firestore doc ids (e.g.
    /// "jaren-jackson-jr." → "jaren-jackson-jr"). nonisolated → unit-testable.
    nonisolated static func canonicalSlug(_ slug: String) -> String {
        guard !slug.isEmpty else { return slug }
        let noDots = slug.replacingOccurrences(of: ".", with: "")
        let collapsed = noDots.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
