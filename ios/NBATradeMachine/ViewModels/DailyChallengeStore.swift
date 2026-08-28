import Foundation
import SwiftUI
import Combine

/// Computes today's Daily + this week's Weekly challenge via the pure
/// `DailyChallengeGenerator`, against an INJECTED `now` (no ambient `Date()` at
/// the type level — the store supplies it so tests are deterministic and devices
/// converge). Reads/writes the local novelty ring buffer (injectable defaults,
/// key `dailyNovelty.v1`) for the DEVICE-LOCAL variety surface only; the shared
/// daily/weekly derive from the date+pool seed alone (Sol A1). Injected app-wide
/// at the ContentView root.
@MainActor
final class DailyChallengeStore: ObservableObject {

    static let noveltyKey = "dailyNovelty.v1"
    static let playedKeyPrefix = "dailyPlayed.v1."
    private static let maxNovelty = 12

    @Published private(set) var daily: DailyChallenge
    @Published private(set) var weekly: DailyChallenge

    private let defaults: UserDefaults
    private let poolVersion: String
    private let nowProvider: () -> Date
    /// The most recent live pool handed in via `validate(against:)`. Retained so a
    /// `refresh()` (which recomputes both challenges from scratch) re-applies the
    /// live-pool feasibility swap instead of reverting to a possibly-infeasible
    /// generated challenge (Sol fix 2). Empty until the first non-empty validate.
    private var livePool: [GameEntityRecord] = []

    /// `now` is injected (a closure so the store re-reads the clock on refresh).
    /// `poolVersion` folds the current-era pool identity into the canonical seed
    /// (risk §133) so a mid-day roster refresh yields a fresh, still-feasible seed.
    init(defaults: UserDefaults = .standard,
         poolVersion: String = "current-v1",
         now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.poolVersion = poolVersion
        self.nowProvider = now
        let n = now()
        self.daily = DailyChallengeGenerator.generate(
            cadence: .daily, calendarDate: n, poolVersion: poolVersion)
        self.weekly = DailyChallengeGenerator.generate(
            cadence: .weekly, calendarDate: n, poolVersion: poolVersion)
    }

    nonisolated deinit {}

    /// Recompute both challenges for the current `now` (call on appear / date
    /// rollover). Idempotent within a period — the same UTC day/week yields the
    /// same challenge.
    func refresh() {
        let n = nowProvider()
        daily = DailyChallengeGenerator.generate(
            cadence: .daily, calendarDate: n, poolVersion: poolVersion)
        weekly = DailyChallengeGenerator.generate(
            cadence: .weekly, calendarDate: n, poolVersion: poolVersion)
        // Re-apply the live-pool feasibility swap (Sol fix 2): a fresh generate could
        // resolve to a definition that's infeasible against the current roster.
        if !livePool.isEmpty { validate(against: livePool) }
    }

    // MARK: - Live-pool re-validation (Sol fix 2 / spec §133)

    /// Re-validate the resolved daily + weekly against the LIVE pool and, on
    /// infeasibility, deterministically substitute the corresponding SAFE base
    /// preset (same cadence/date/seed). The deterministic `generate` stays pure; this
    /// validate+swap is a separate step so tests of the generator remain deterministic.
    /// No-op on an empty pool (players not loaded yet) so a cold start never
    /// downgrades a valid daily to the safe preset before the roster arrives.
    func validate(against pool: [GameEntityRecord]) {
        guard !pool.isEmpty else { return }
        livePool = pool
        daily = revalidated(daily, pool: pool)
        weekly = revalidated(weekly, pool: pool)
    }

    /// A challenge validated against `pool`: itself when feasible, else the safe
    /// base-preset substitute preserving cadence/date/seed.
    private func revalidated(_ challenge: DailyChallenge,
                             pool: [GameEntityRecord]) -> DailyChallenge {
        let draft = GameDraft(id: challenge.id, title: challenge.title,
                              payload: challenge.payload)
        switch GameDefinitionValidator.validate(draft, pool: pool) {
        case .success:
            return challenge
        case .failure:
            let safe = DailyChallengeGenerator.safeLaunch(for: challenge.payload.family)
            return DailyChallengeGenerator.challenge(
                from: safe, cadence: challenge.cadence,
                dateKey: challenge.dateKey, seed: challenge.seed)
        }
    }

    // MARK: - Played flag

    func hasPlayed(_ challenge: DailyChallenge) -> Bool {
        defaults.bool(forKey: Self.playedKeyPrefix + challenge.id)
    }

    /// Mark a challenge played today + record its fingerprint in the ring buffer.
    func markPlayed(_ challenge: DailyChallenge) {
        defaults.set(true, forKey: Self.playedKeyPrefix + challenge.id)
        recordNovelty(challenge.noveltyFingerprint)
    }

    // MARK: - Novelty ring buffer (device-local)

    func recentFingerprints() -> [String] {
        defaults.stringArray(forKey: Self.noveltyKey) ?? []
    }

    private func recordNovelty(_ fp: String) {
        var buffer = recentFingerprints()
        buffer.removeAll { $0 == fp }
        buffer.append(fp)
        if buffer.count > Self.maxNovelty { buffer.removeFirst(buffer.count - Self.maxNovelty) }
        defaults.set(buffer, forKey: Self.noveltyKey)
    }
}
