import Foundation

/// The fantasy season window derived from the league calendar's NBA milestones —
/// the same calendar that determines off/on-season. The fantasy REGULAR season
/// runs from the NBA `regularStart` up to `playoffsStart` (fantasy leagues wrap
/// their regular season as the NBA playoffs begin). Pure + timezone-pinned to the
/// league's calendar (US-Eastern, matching the game-date strings), so "what week
/// is it" is consistent regardless of device timezone.
nonisolated struct FantasyCalendar: Equatable {
    /// NBA regular-season start (fantasy season start). nil → calendar unavailable.
    let seasonStart: Date?
    /// NBA playoffs start (fantasy regular-season end). nil → calendar unavailable.
    let seasonEnd: Date?

    static let none = FantasyCalendar(seasonStart: nil, seasonEnd: nil)

    /// The league's calendar timezone — day boundaries + week math use this, NOT
    /// the device zone (the milestone strings are US-Eastern dates).
    static let zone = TimeZone(identifier: "America/New_York") ?? .current

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    static func from(_ windows: [String: String]?) -> FantasyCalendar {
        FantasyCalendar(seasonStart: parseDate(windows?["regularStart"]),
                        seasonEnd: parseDate(windows?["playoffsStart"]))
    }

    /// Parse a "YYYY-MM-DD" milestone as start-of-day in the league zone.
    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = zone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: s)
    }

    var isConfigured: Bool { seasonStart != nil && seasonEnd != nil }

    /// Whole fantasy weeks between start and end (each 7 days). nil when unconfigured.
    var totalWeeks: Int? {
        guard let s = seasonStart, let e = seasonEnd, e > s else { return nil }
        let days = Self.calendar.dateComponents([.day], from: startOfDay(s), to: startOfDay(e)).day ?? 0
        return max(1, Int((Double(days) / 7.0).rounded(.up)))
    }

    // MARK: Status

    enum Status: Equatable {
        case unknown                                  // no calendar
        case preseason(daysUntilStart: Int)           // before regularStart
        case active(week: Int, of: Int)               // in season (1-based week)
        case postseason                               // at/after playoffsStart
    }

    func status(on now: Date) -> Status {
        guard let start = seasonStart, let end = seasonEnd, let total = totalWeeks else { return .unknown }
        let today = startOfDay(now)
        if today < startOfDay(start) {
            let days = Self.calendar.dateComponents([.day], from: today, to: startOfDay(start)).day ?? 0
            return .preseason(daysUntilStart: max(0, days))
        }
        if today >= startOfDay(end) { return .postseason }
        return .active(week: weekIndex(on: now) ?? 1, of: total)
    }

    /// 1-based fantasy week for `now` (1 during the first 7 days). nil outside the
    /// season or when unconfigured.
    func weekIndex(on now: Date) -> Int? {
        guard let start = seasonStart, let end = seasonEnd else { return nil }
        let today = startOfDay(now)
        guard today >= startOfDay(start), today < startOfDay(end) else { return nil }
        let days = Self.calendar.dateComponents([.day], from: startOfDay(start), to: today).day ?? 0
        return days / 7 + 1
    }

    /// The [start, end) date range for a 1-based fantasy `week`, anchored at
    /// `seasonStart + (week-1)*7 days` and CLAMPED to the exclusive season end.
    /// nil when unconfigured, week < 1, or the week starts at/after the season end
    /// (so labels never overshoot playoffsStart or point into the offseason).
    func weekDateRange(week: Int) -> (start: Date, end: Date)? {
        guard let start = seasonStart, let end = seasonEnd, week >= 1 else { return nil }
        let cal = Self.calendar
        let seasonEndDay = startOfDay(end)
        guard let s = cal.date(byAdding: .day, value: (week - 1) * 7, to: startOfDay(start)),
              s < seasonEndDay else { return nil }               // week entirely past the season
        let rawEnd = cal.date(byAdding: .day, value: 7, to: s) ?? s
        let e = min(rawEnd, seasonEndDay)                        // clamp the final partial week
        guard e > s else { return nil }
        return (s, e)
    }

    /// "Mon Jan 5 – Sun Jan 11"-style label for a fantasy week (end is inclusive).
    func weekLabel(week: Int) -> String? {
        guard let range = weekDateRange(week: week) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = Self.zone
        fmt.dateFormat = "MMM d"
        let lastDay = Self.calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(fmt.string(from: range.start)) – \(fmt.string(from: lastDay))"
    }

    private func startOfDay(_ d: Date) -> Date { Self.calendar.startOfDay(for: d) }
}
