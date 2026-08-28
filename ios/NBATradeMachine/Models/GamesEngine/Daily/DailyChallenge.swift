import Foundation

nonisolated enum ChallengeCadence: String, Codable, Equatable { case daily, weekly }

/// A generated Daily/Weekly challenge. Carries a `GameDraft.Payload` (a full,
/// Codable engine definition) so it dispatches through the SAME `GameLauncher` /
/// gameplay views as a preset. `noveltyFingerprint` is DEVICE-LOCAL variety only
/// (Sol A1) — it is NOT part of the globally shared challenge, so two devices
/// with different play histories still see the same daily game.
nonisolated struct DailyChallenge: Codable, Equatable, Identifiable {
    let cadence: ChallengeCadence
    let dateKey: String              // canonical UTC key ("2026-08-27" / "2026-W35")
    let title: String
    let payload: GameDraft.Payload
    let noveltyFingerprint: String
    /// The CANONICAL engine seed for the shared-challenge play (Sol fix 1). Derived
    /// from the same (cadence, dateKey, poolVersion) as the definition, so every
    /// device that day initializes the engine with byte-identical entities (the
    /// bracket field / the ranked subjects / the higher-lower pair). Without this,
    /// each device's gameplay view rolled `UInt64.random(...)` and diverged, so the
    /// "same game everywhere today" guarantee only held for the Definition, not the
    /// actual playable state.
    let seed: UInt64

    /// Stable identity: cadence + the period key.
    var id: String { "\(cadence.rawValue)|\(dateKey)" }

    func toLaunch() -> GameLaunch {
        switch payload {
        case .roster(let d):         return .roster(d)
        case .classification(let d): return .classification(d)
        case .compare(let d):        return .compare(d)
        case .bracket(let d):        return .bracket(d)
        }
    }
}

/// Pure nonisolated Daily/Weekly generator (Sol A1). The GLOBALLY SHARED
/// challenge derives ONLY from the canonical versioned seed
/// `"challenge-v1|<utcDateKey>|<poolVersion>"` (date + pool version), so every
/// device that day computes byte-identical output. The optional
/// `recentFingerprints` buffer is DEVICE-LOCAL variety layered on top and must
/// NEVER influence the shared challenge (risk §131) — it's used only to re-roll a
/// NON-SHARED "surprise me" surface. The store passes an empty buffer for the
/// shared daily/weekly.
nonisolated enum DailyChallengeGenerator {

    static let seedVersion = "challenge-v1"

    /// The base presets the generator rotates across (all shipped families). Order
    /// is stable — the seed indexes into it. Computed (not a stored `static let`)
    /// because `GameLaunch` is non-Sendable, so a stored static would be flagged as
    /// shared mutable state under Swift 6 concurrency checking.
    static var basePresets: [GameLaunch] {
        [
            .roster(GamePresets.bestCurrentPlayers),
            .classification(ClassificationPresets.rankPlayers),
            .compare(ComparePresets.higherRated),
            .bracket(BracketPresets.quickBracket),
        ]
    }

    // MARK: - Date keys

    /// UTC "yyyy-MM-dd" for a daily key.
    static func dailyKey(_ date: Date, calendar: Calendar = .utc) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// UTC ISO week key "yyyy-Www" for a weekly key (so a whole week shares one).
    static func weeklyKey(_ date: Date, calendar: Calendar = .utc) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    static func dateKey(for cadence: ChallengeCadence, date: Date,
                        calendar: Calendar = .utc) -> String {
        switch cadence {
        case .daily:  return dailyKey(date, calendar: calendar)
        case .weekly: return weeklyKey(date, calendar: calendar)
        }
    }

    // MARK: - Generate

    /// Generate the challenge for a cadence + calendar date + pool version. The
    /// SHARED derivation uses only (cadence, dateKey, poolVersion). If
    /// `recentFingerprints` is non-empty AND a variety re-roll is requested
    /// (`allowNoveltyReroll`), the generator perturbs the SEED (device-local) to
    /// avoid a recent fingerprint — used ONLY for the non-shared surface. For the
    /// shared daily/weekly, pass `allowNoveltyReroll: false` (the default) so the
    /// output stays date-deterministic.
    static func generate(cadence: ChallengeCadence,
                         calendarDate: Date,
                         poolVersion: String,
                         recentFingerprints: [String] = [],
                         allowNoveltyReroll: Bool = false,
                         calendar: Calendar = .utc) -> DailyChallenge {
        let key = dateKey(for: cadence, date: calendarDate, calendar: calendar)
        var attempt = 0
        while true {
            let seedString = "\(seedVersion)|\(cadence.rawValue)|\(key)|\(poolVersion)|\(attempt)"
            let seed = NoveltyFingerprint.fnv1a(seedString)
            let launch = build(cadence: cadence, seed: seed)
            let fp = NoveltyFingerprint.fingerprint(launch)
            let collides = allowNoveltyReroll
                && recentFingerprints.contains(fp)
                && attempt < 8            // bounded re-rolls
            if !collides {
                let payload = payload(from: launch)
                // Canonical PLAY seed (Sol fix 1): same (cadence, dateKey, poolVersion)
                // ⇒ identical seed on every device, so the shared challenge plays the
                // SAME entities everywhere — not just the same Definition. The "|play"
                // namespace keeps it distinct from the build-attempt seed above.
                let playSeed = NoveltyFingerprint.fnv1a(
                    "\(seedVersion)|\(cadence.rawValue)|\(key)|\(poolVersion)|play")
                return DailyChallenge(cadence: cadence, dateKey: key,
                                      title: title(for: launch, cadence: cadence),
                                      payload: payload, noveltyFingerprint: fp,
                                      seed: playSeed)
            }
            attempt += 1
        }
    }

    /// The SAFE, known-feasible base preset for a family (Sol fix 2). Used to
    /// substitute an infeasible resolved daily/weekly (e.g. a bracket-16 against a
    /// shrunken live pool) with a launch the engine can always complete. These are
    /// the shipped presets each engine's `initialize` is guaranteed to run.
    static func safeLaunch(for family: CreatorOptions.EngineFamily) -> GameLaunch {
        switch family {
        case .roster:         return .roster(GamePresets.bestCurrentPlayers)
        case .classification: return .classification(ClassificationPresets.rankPlayers)
        case .compare:        return .compare(ComparePresets.higherRated)
        case .bracket:        return .bracket(BracketPresets.quickBracket)
        }
    }

    /// Wrap an explicit `GameLaunch` into a `DailyChallenge`, preserving the
    /// challenge's cadence/date/seed (Sol fix 2). Used ONLY by the store's live-pool
    /// re-validation fallback — the deterministic `generate` itself stays pure, so
    /// tests remain deterministic; the validate+swap is a separate, explicit step.
    static func challenge(from launch: GameLaunch, cadence: ChallengeCadence,
                          dateKey: String, seed: UInt64) -> DailyChallenge {
        DailyChallenge(cadence: cadence, dateKey: dateKey,
                       title: title(for: launch, cadence: cadence),
                       payload: payload(from: launch),
                       noveltyFingerprint: NoveltyFingerprint.fingerprint(launch),
                       seed: seed)
    }

    // MARK: - Build (seed → definition)

    /// Pick a base preset by the seed and deterministically fill its open
    /// parameters. Weekly biases toward the longer builds (roster / bracket).
    static func build(cadence: ChallengeCadence, seed: UInt64) -> GameLaunch {
        var rng = SeededRNG(seed: seed)
        let index: Int
        switch cadence {
        case .weekly:
            // Longer builds: roster (0) or bracket (3).
            index = Bool.random(using: &rng) ? 0 : 3
        case .daily:
            index = Int(rng.next() % UInt64(basePresets.count))
        }
        let base = basePresets[index]
        return fillParameters(base, rng: &rng)
    }

    /// Deterministically vary a base preset's open knobs from the RNG so the daily
    /// isn't always literally the shipped preset. Each variation stays a legal
    /// Definition the engine already runs.
    static func fillParameters(_ base: GameLaunch, rng: inout SeededRNG) -> GameLaunch {
        switch base {
        case .roster(let d):
            // Vary the roster shape between flexFive and a positionless(5).
            let shape: RosterConfig = Bool.random(using: &rng) ? .flexFive : .positionless(5)
            let def = GameDefinition(
                id: d.id, title: d.title, engineType: d.engineType,
                entityConstraints: d.entityConstraints,
                rosterConstraints: d.rosterConstraints, roster: shape,
                selection: d.selection, scoring: d.scoring,
                economy: d.economy, reveal: d.reveal,
                specialActions: d.specialActions, poolSource: d.poolSource)
            return .roster(def)
        case .compare(let d):
            // Vary the metric across overall/offense/defense.
            let metrics: [CompareMetric] = [.overall, .offense, .defense]
            let m = metrics[Int(rng.next() % UInt64(metrics.count))]
            let def = CompareDefinition(id: d.id, title: d.title,
                                        config: CompareConfig(metric: m, direction: .higher))
            return .compare(def)
        case .bracket(let d):
            // Vary the field size across 4/8/16 (keep the preset's scoring).
            let sizes = [4, 8, 16]
            let size = sizes[Int(rng.next() % UInt64(sizes.count))]
            let def = BracketDefinition(id: d.id, title: d.title, fieldSize: size,
                                        seedByRating: d.seedByRating,
                                        entityConstraints: d.entityConstraints,
                                        scoring: d.scoring)
            return .bracket(def)
        case .classification(let d):
            // Vary the subject count across 6/8/10 for a totalOrder rank.
            let counts = [6, 8, 10]
            let n = counts[Int(rng.next() % UInt64(counts.count))]
            let def = ClassificationDefinition(id: d.id, title: d.title,
                config: ClassificationConfig(mode: d.config.mode, labels: d.config.labels,
                                             subjectCount: n,
                                             candidatePoolSize: d.config.candidatePoolSize))
            return .classification(def)
        case .guess, .quiz, .survivor, .grid, .connection:
            // Phase-5/6 single-player families aren't part of the daily rotation
            // (not in `basePresets`), so there are no knobs to vary here — pass
            // through unchanged. (Kept exhaustive so the compiler enforces that any
            // future daily-rotation addition is handled explicitly.)
            return base
        case .none:
            return base
        }
    }

    // MARK: - Helpers

    static func payload(from launch: GameLaunch) -> GameDraft.Payload {
        switch launch {
        case .roster(let d):         return .roster(d)
        case .classification(let d): return .classification(d)
        case .compare(let d):        return .compare(d)
        case .bracket(let d):        return .bracket(d)
        // Phase-5/6 families have no GameDraft.Payload case and are never generated
        // by the daily rotation → unreachable; fall back to a known-safe payload.
        case .guess, .quiz, .survivor, .grid, .connection, .none:
            return .roster(GamePresets.bestCurrentPlayers)  // unreachable
        }
    }

    static func title(for launch: GameLaunch, cadence: ChallengeCadence) -> String {
        let prefix = cadence == .daily ? "Daily" : "Weekly"
        let base: String
        switch launch {
        case .roster(let d):         base = d.title
        case .classification(let d): base = d.title
        case .compare(let d):        base = d.title
        case .bracket(let d):        base = d.title
        case .guess(let d):          base = d.title
        case .quiz(let d):           base = d.title
        case .survivor(let d):       base = d.title
        case .grid(let d):           base = d.title
        case .connection(let d):     base = d.title
        case .none:                  base = "Challenge"
        }
        return "\(prefix): \(base)"
    }
}

nonisolated extension Calendar {
    /// A UTC Gregorian calendar (the canonical calendar for date-seeded keys, so
    /// every device converges regardless of local timezone).
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}
