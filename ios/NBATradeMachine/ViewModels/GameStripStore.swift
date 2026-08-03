import Foundation
import Combine

/// Loads a bounded window of `games` docs once and serves the News tab's
/// date-navigable regular-season strip. Mirrors `TodayGamesStore` (load-once
/// guard, `FantasyPhase`, seam-injected service, ET `leagueTimeZone`, day-rollover
/// re-fetch). `.empty` is the normal offseason state (no docs in range → the strip
/// renders nothing), not an error.
@MainActor
final class GameStripStore: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published private(set) var daysWithGames: [String] = []   // sorted ascending
    @Published private(set) var selectedDate: String?
    @Published private(set) var phase: FantasyPhase = .idle

    /// `gameDate` strings are US-Eastern game dates — pin "today" to the league's
    /// calendar, not the device's (mirror `TodayGamesStore`).
    static let leagueTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    /// ±N-day presence window around today. Enough to find the nearest slate across
    /// an off-night without unbounded reads; regular-season-only ingest makes an
    /// empty window == offseason.
    static let windowDays = 10

    private var gamesByDate: [String: [GameDay]] = [:]
    private var loadedDate: String?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func games(on date: String) -> [GameDay] { gamesByDate[date] ?? [] }

    func load(now: Date = Date()) async {
        guard phase != .loading else { return }
        let today = GameDaySchedule.todayString(now: now, timeZone: Self.leagueTimeZone)
        if loadedDate == today && phase != .failed { return }   // same-day + fresh → no-op
        phase = .loading
        let (from, to) = Self.window(around: today)
        do {
            let games = try await service.fetchGames(from: from, to: to)
            let grouped = GameStripLogic.groupByDate(games)
            gamesByDate = grouped
            daysWithGames = grouped.keys.sorted()
            selectedDate = GameStripLogic.nearestDay(to: today, in: daysWithGames)
            phase = daysWithGames.isEmpty ? .empty : .loaded
            loadedDate = today
        } catch {
            // A failed window read has no valid slate; clear so nothing stale renders
            // and surface .failed. loadedDate stays stale so the next appear retries.
            gamesByDate = [:]; daysWithGames = []; selectedDate = nil
            phase = .failed
        }
    }

    /// Move the selection to the adjacent game day, if one exists (no-op at the ends).
    func step(_ direction: GameStripLogic.Direction) {
        guard let current = selectedDate,
              let next = GameStripLogic.adjacentDay(from: current, direction: direction, in: daysWithGames)
        else { return }
        selectedDate = next
    }

    /// Whether an arrow in `direction` has a target (drives the view's `.disabled`).
    func canStep(_ direction: GameStripLogic.Direction) -> Bool {
        guard let current = selectedDate else { return false }
        return GameStripLogic.adjacentDay(from: current, direction: direction, in: daysWithGames) != nil
    }

    private static func window(around today: String) -> (String, String) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let base = fmt.date(from: today) else { return (today, today) }
        let from = base.addingTimeInterval(TimeInterval(-windowDays * 86_400))
        let to = base.addingTimeInterval(TimeInterval(windowDays * 86_400))
        return (fmt.string(from: from), fmt.string(from: to))
    }
}
