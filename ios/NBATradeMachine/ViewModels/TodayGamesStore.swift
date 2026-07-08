import Foundation
import Combine

/// Loads today's `games` docs once and serves the set of team ids with a game
/// today — the "is he playing tonight" signal for the fantasy team grade card.
/// Mirrors `FantasyActualsStore` (load-once guard, `FantasyPhase`, seam-injected
/// service). `.empty` is the normal offseason/no-games-today state, not an error.
@MainActor
final class TodayGamesStore: ObservableObject {
    @Published private(set) var teamsPlayingToday: Set<String> = []
    @Published private(set) var phase: FantasyPhase = .idle

    /// `gameDate` strings are US-Eastern game dates (the ingest writes the
    /// schedule's `gameDateEst`), so "today" is pinned to the league's calendar,
    /// not the device's — a user in Europe at 2am still sees tonight's ET slate.
    static let leagueTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    /// The date string the current slate was loaded for — a day rollover (app
    /// resident past midnight, re-foregrounded tomorrow) triggers a re-fetch
    /// instead of serving yesterday's slate for the whole process lifetime.
    private var loadedDate: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load(now: Date = Date()) async {
        guard phase != .loading else { return }
        let today = GameDaySchedule.todayString(now: now, timeZone: Self.leagueTimeZone)
        if loadedDate == today && phase != .failed { return }   // same-day + fresh → no-op
        phase = .loading
        do {
            let games = try await service.fetchGames(on: today)
            teamsPlayingToday = GameDaySchedule.teamsPlaying(games: games, on: today)
            phase = teamsPlayingToday.isEmpty ? .empty : .loaded
            loadedDate = today
        } catch {
            // A failed fetch means we have no valid slate for `today`. The load-once guard only
            // re-fetches on a DAY ROLLOVER (or a .failed retry), so any slate still held here is
            // for a PREVIOUS date — it must NOT be presented as tonight's games (a stale "playing
            // today" signal is worse than an honest "Schedule unavailable"). Clear it and surface
            // .failed; `loadedDate` stays stale so the next foreground/reconnect retries.
            teamsPlayingToday = []
            phase = .failed
        }
    }
}
