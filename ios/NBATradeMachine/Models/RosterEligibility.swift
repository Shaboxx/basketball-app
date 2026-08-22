import Foundation

/// Maps each (player-slug, team-UUID) pair to the list of `DateInterval`s during which that
/// player's games count for that team. The fundamental scoring invariant:
///
///   A game at `gameDate` counts for team T iff `RosterEligibility.isEligible(_:team:on:)`
///   returns `true` — i.e. some interval satisfies `start <= gameDate < end` (HALF-OPEN).
///
/// IMPORTANT — half-open semantics: the spec (see docs/fantasy-weekly-scoring-spec.md) mandates
/// intervals `[effectiveFrom, effectiveUntil)`. `DateInterval.contains(_:)` is END-INCLUSIVE
/// (closed `[start, end]`), so a game whose timestamp equals a trade/add boundary would be
/// counted on BOTH the outgoing team (closed end) AND the incoming team (open start) — a
/// double-count. Callers MUST therefore query eligibility through `isEligible(_:team:on:)`
/// (which uses strict `< end`) and MUST NOT call `DateInterval.contains` on the raw windows
/// returned by `window(of:team:)`.
///
/// Two factory methods cover the two league kinds:
///   • `.alwaysCurrent` — local leagues / hosted leagues that predate the transaction log.
///     Every current member gets one open-ended interval from the distant past.
///   • `HostedTransactionTimeline.build` — reconstructs history from the `transactions`
///     subcollection (draftComplete, trade, addDrop docs), returning `nil` when there is
///     no `draftComplete` doc so callers can fall back to `.alwaysCurrent`.
///
/// All slug comparisons go through `FantasyValueStore.canonicalSlug` so "jaren-jackson-jr."
/// and "jaren-jackson-jr" resolve to the same key. Pure + `nonisolated` — no store access.
nonisolated struct RosterEligibility {

    // MARK: Storage

    /// (canonicalSlug, teamId) → ordered, non-overlapping windows during which the player
    /// is on that team. `end == .distantFuture` means "still on the team".
    private let intervals: [SlugTeamKey: [DateInterval]]

    fileprivate struct SlugTeamKey: Hashable {
        let slug: String    // canonical
        let team: UUID
    }

    // MARK: Query

    /// Returns every `DateInterval` during which `slug` was rostered for `team`.
    /// An empty array means the player was never on that team (all games excluded).
    ///
    /// - Warning: The returned intervals are stored as `DateInterval` for convenience, but the
    ///   scoring invariant is HALF-OPEN `[start, end)`. Do NOT call `DateInterval.contains(_:)`
    ///   on these — it is end-inclusive and will double-count games that fall exactly on a
    ///   trade/add boundary. Use `isEligible(_:team:on:)` instead.
    func window(of slug: String, team: UUID) -> [DateInterval] {
        let key = SlugTeamKey(slug: FantasyValueStore.canonicalSlug(slug), team: team)
        return intervals[key] ?? []
    }

    /// Canonical eligibility test with correct HALF-OPEN `[start, end)` semantics: a game at
    /// `date` counts for `team` iff some window satisfies `start <= date && date < end`.
    ///
    /// This is the ONLY membership check callers (e.g. `FantasyWeekAggregator`) should use.
    /// Because the end is strictly exclusive, a game whose timestamp equals a trade/add
    /// boundary is attributed to exactly one team (the incoming one), never both.
    func isEligible(_ slug: String, team: UUID, on date: Date) -> Bool {
        let key = SlugTeamKey(slug: FantasyValueStore.canonicalSlug(slug), team: team)
        guard let windows = intervals[key] else { return false }
        for w in windows where w.start <= date && date < w.end {
            return true
        }
        return false
    }

    // MARK: Factory — local / fallback

    /// Every player in the supplied rosters gets one open-ended interval
    /// [.distantPast, .distantFuture), making every game eligible. Use for local leagues
    /// or any hosted league that lacks a `draftComplete` transaction.
    ///
    /// - Parameter rosters: teamId → [playerSlug] (current rosters).
    static func alwaysCurrent(rosters: [UUID: [String]]) -> RosterEligibility {
        var map: [SlugTeamKey: [DateInterval]] = [:]
        for (teamId, slugs) in rosters {
            for slug in slugs {
                let key = SlugTeamKey(slug: FantasyValueStore.canonicalSlug(slug), team: teamId)
                map[key, default: []].append(DateInterval(start: .distantPast, end: .distantFuture))
            }
        }
        return RosterEligibility(intervals: map)
    }

    // MARK: Internal memberwise init (used by HostedTransactionTimeline)

    fileprivate init(intervals: [SlugTeamKey: [DateInterval]]) {
        self.intervals = intervals
    }
}

// MARK: - HostedTransactionTimeline

/// Pure builder that reconstructs `RosterEligibility` from the `transactions` subcollection.
/// Processing order:
///  1. `draftComplete` — its `at` timestamp opens the initial roster intervals.
///  2. `trade` docs (sorted by `at`) — each moves slugs between teams at the trade timestamp.
///  3. `addDrop` docs (sorted by `at`) — each opens the added player's interval and closes
///     the dropped player's interval at the same timestamp.
///
/// All timestamps from `HostedTransaction.at` (SERVER_TIMESTAMP). Docs whose `at` is `nil`
/// (pending server write) are silently skipped — they will be applied once the timestamp arrives.
nonisolated enum HostedTransactionTimeline {

    // MARK: Build

    /// Reconstruct roster eligibility from a flat list of `HostedTransaction` docs.
    ///
    /// - Parameters:
    ///   - transactions: All docs from `hostedLeagues/{id}/transactions`, in any order.
    ///   - draftRosters: The roster each team held at draft completion (uid → [slug]).
    ///     Used to open the initial intervals when the `draftComplete` doc is found.
    ///   - uidToTeamId: Maps a Firebase uid to the engine's `UUID` for that team.
    ///     Typically `HostedTeamKey.uuid(forUid:)`.
    /// - Returns: `nil` if no `draftComplete` doc with a non-nil `at` is found, signalling
    ///   the caller to fall back to `.alwaysCurrent`.
    static func build(
        transactions: [HostedTransaction],
        draftRosters: [UUID: [String]],
        uidToTeamId: (String) -> UUID?
    ) -> RosterEligibility? {

        // Find the draftComplete doc — the anchor for the entire timeline.
        guard let draftDoc = transactions.first(where: { $0.type == "draftComplete" }),
              let draftAt = draftDoc.at else {
            return nil   // no completed draft → caller falls back to .alwaysCurrent
        }

        // --- MUTABLE STATE ---
        // open[slug][team] = when that interval started (nil means not currently on that team)
        var open: [String: [UUID: Date]] = [:]
        // closed intervals accumulated so far
        var intervals: [RosterEligibility.SlugTeamKey: [DateInterval]] = [:]

        // MARK: Helpers

        func canonicalize(_ slug: String) -> String { FantasyValueStore.canonicalSlug(slug) }

        /// Open a new interval for (slug, team) starting at `date`.
        func beginInterval(slug: String, team: UUID, at date: Date) {
            let c = canonicalize(slug)
            open[c, default: [:]][team] = date
        }

        /// Close the interval for (slug, team) at `date` and record it.
        func endInterval(slug: String, team: UUID, at date: Date) {
            let c = canonicalize(slug)
            guard let start = open[c]?[team] else { return }
            // Only record a positive-length interval.
            if date > start {
                let key = RosterEligibility.SlugTeamKey(slug: c, team: team)
                intervals[key, default: []].append(DateInterval(start: start, end: date))
            }
            open[c]?[team] = nil
        }

        // MARK: 1. Draft — open initial intervals from draftRosters at draftAt

        for (teamId, slugs) in draftRosters {
            for slug in slugs {
                beginInterval(slug: slug, team: teamId, at: draftAt)
            }
        }

        // MARK: 2. Process post-draft transactions chronologically

        let postDraft = transactions
            .filter { $0.type == "trade" || $0.type == "addDrop" }
            .compactMap { tx -> (HostedTransaction, Date)? in
                guard let at = tx.at else { return nil }
                return (tx, at)
            }
            .sorted { $0.1 < $1.1 }

        for (tx, at) in postDraft {
            switch tx.type {

            case "trade":
                guard let fromUid = tx.fromUid,
                      let toUid   = tx.toUid,
                      let fromTeam = uidToTeamId(fromUid),
                      let toTeam   = uidToTeamId(toUid) else { continue }

                // Players going from → to
                for slug in tx.fromSlugs ?? [] {
                    endInterval(slug: slug, team: fromTeam, at: at)
                    beginInterval(slug: slug, team: toTeam,   at: at)
                }
                // Players going to → from
                for slug in tx.toSlugs ?? [] {
                    endInterval(slug: slug, team: toTeam,   at: at)
                    beginInterval(slug: slug, team: fromTeam, at: at)
                }

            case "addDrop":
                guard let uid    = tx.uid,
                      let team   = uidToTeamId(uid) else { continue }

                // Close the dropped player's interval (if any)
                if let dropSlug = tx.dropSlug {
                    endInterval(slug: dropSlug, team: team, at: at)
                }
                // Open the added player's interval
                if let addSlug = tx.addSlug {
                    beginInterval(slug: addSlug, team: team, at: at)
                }

            default:
                break
            }
        }

        // MARK: 3. Close all still-open intervals to .distantFuture

        for (slug, teamMap) in open {
            for (team, start) in teamMap {
                let key = RosterEligibility.SlugTeamKey(slug: slug, team: team)
                intervals[key, default: []].append(
                    DateInterval(start: start, end: .distantFuture))
            }
        }

        return RosterEligibility(intervals: intervals)
    }
}

// MARK: - RosterEligibility.SlugTeamKey public surface

// The key is a private implementation detail; expose what tests need via the query surface only.
// (Intentionally no public accessor — callers always go through `window(of:team:)`.)
