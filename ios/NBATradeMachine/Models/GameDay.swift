import Foundation

/// Minimal decode of a `games/{id}` doc — just enough to answer "who plays on
/// this date". Every field optional (synthesized Codable → decodeIfPresent) so a
/// scheduled game with null scores or a partial doc still decodes.
nonisolated struct GameDay: Codable, Equatable {
    let gameId: String?
    let gameDate: String?     // "yyyy-MM-dd"
    let homeTeamId: String?
    let awayTeamId: String?
    let status: String?
}

nonisolated enum GameDaySchedule {

    /// Team ids appearing on either side of any game on `date`.
    static func teamsPlaying(games: [GameDay], on date: String) -> Set<String> {
        var out = Set<String>()
        for g in games where g.gameDate == date {
            if let h = g.homeTeamId { out.insert(h) }
            if let a = g.awayTeamId { out.insert(a) }
        }
        return out
    }

    /// "yyyy-MM-dd" for `now` in the given time zone. NOTE: the ingest writes
    /// `gameDate` from the schedule's `gameDateEst` (a US-Eastern game date), so
    /// callers matching against it must pass `TodayGamesStore.leagueTimeZone`,
    /// not the device zone.
    static func todayString(now: Date, timeZone: TimeZone = .current) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: now)
    }
}
