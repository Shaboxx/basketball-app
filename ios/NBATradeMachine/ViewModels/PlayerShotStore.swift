import Foundation
import Combine

/// Loads the whole `playerShots` collection once, keyed by canonical slug, plus the league
/// per-cell baseline (`_league`). The bundle seeds `league`/`leagueMeanPPS` at the top of
/// `load()`; a VALID fetch replaces the seed (Firestore authoritative), an invalid/throwing
/// fetch leaves the seed in place (section 8.3). In-memory per session (no disk cache, F4).
@MainActor
final class PlayerShotStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    static let shared = PlayerShotStore()
    @Published private(set) var charts: [String: PlayerShotChart] = [:]
    @Published private(set) var phase: FantasyPhase = .idle
    /// The validated 624-double league baseline (NaN where a cell is null), or nil when
    /// neither Firestore nor the bundle supplied a valid field.
    @Published private(set) var league: [Double]? = nil
    @Published private(set) var leagueMeanPPS: Double? = nil
    /// PF9: a monotonic counter bumped on EVERY league/leagueMeanPPS assignment (seed AND valid
    /// replacement). Views key their rebuild `.task` id on this Int (NOT the `league != nil`
    /// boolean), so replacing a non-nil seed with a valid fetched field STILL re-fires the rebuild
    /// (a boolean would not change nil->non-nil in that case). Starts at 0; only `assignLeague`
    /// mutates it.
    @Published private(set) var leagueRevision: Int = 0
    private let service: FirestoreReading
    /// Injectable bundle seed (PF8): defaults to the app bundle at runtime; tests inject a seed
    /// directly instead of relying on test-host resource packaging.
    private let seed: (baseline: [Double]?, pps: Double?)
    init(service: FirestoreReading = FirestoreService.shared,
         seed: (baseline: [Double]?, pps: Double?)? = nil) {
        self.service = service
        self.seed = seed ?? Self.bundledLeagueField()
    }

    /// The ONLY mutator of `league`/`leagueMeanPPS` — bumps `leagueRevision` on every assignment
    /// (seed or valid replacement), even when the assigned value is nil or equal to the prior one.
    private func assignLeague(_ baseline: [Double]?, _ pps: Double?) {
        league = baseline
        leagueMeanPPS = pps
        leagueRevision += 1
    }

    func load() async {
        guard phase == .idle || phase == .failed else { return }
        // Seed UNCONDITIONALLY before any network call (F5) — offline/first launch always has a
        // baseline. A valid fetch replaces it below. Each assignment bumps leagueRevision (PF9).
        assignLeague(seed.baseline, seed.pps)
        phase = .loading
        do {
            let fetched = try await service.fetchPlayerShots()
            charts = fetched.charts
            if let lf = fetched.league, lf.isValid {
                assignLeague(lf.baseline, lf.leagueMeanPPS)   // Firestore wins ONLY with a valid doc
            }                                                 // else: seed (bundle) stays in place
            phase = fetched.charts.isEmpty ? .empty : .loaded
        } catch { phase = .failed }               // seed (bundle) stays in place
    }

    func chart(for slug: String) -> PlayerShotChart? {
        charts[FantasyValueStore.canonicalSlug(slug)]
    }

    /// Decode the app-bundled `league-field.json`, validate it (same `isValid`), and return
    /// (baseline, leagueMeanPPS) — or (nil, nil) when missing/invalid (=> heat unavailable).
    static func bundledLeagueField() -> (baseline: [Double]?, pps: Double?) {
        guard let url = Bundle.main.url(forResource: "league-field", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lf = try? JSONDecoder().decode(LeagueField.self, from: data),
              lf.isValid else { return (nil, nil) }
        return (lf.baseline, lf.leagueMeanPPS)
    }
}
