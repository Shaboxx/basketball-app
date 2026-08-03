import Foundation

/// One matchup cell for the News game strip. `awayTricode`/`homeTricode` == the
/// team ids (the ingest stores tricodes, which `TeamLogoMark` renders directly),
/// exposed under both names so the view reads intently. `trailing` is the
/// final score ("104–112", away–home, en dash) or a schedule label.
nonisolated struct GameStripCell: Equatable {
    let awayTricode: String
    let homeTricode: String
    let awayTeamId: String
    let homeTeamId: String
    let trailing: String
}

/// Pure, testable logic for the News regular-season game strip. No I/O, no dates
/// beyond lexical "yyyy-MM-dd" comparison (lexical order == chronological).
nonisolated enum GameStripLogic {

    enum Direction { case prev, next }

    /// Buckets games by their `gameDate`; games with a nil `gameDate` are dropped.
    static func groupByDate(_ games: [GameDay]) -> [String: [GameDay]] {
        var out: [String: [GameDay]] = [:]
        for g in games {
            guard let d = g.gameDate else { continue }
            out[d, default: []].append(g)
        }
        return out
    }

    /// The day to anchor on: `today` if it has games, else the day whose distance
    /// to `today` is smallest — ties (equal distance past vs. future) prefer the
    /// **upcoming** day. Nil only when `days` is empty. `days` need not be sorted.
    static func nearestDay(to today: String, in days: [String]) -> String? {
        guard !days.isEmpty else { return nil }
        if days.contains(today) { return today }
        // distance in whole days; parse "yyyy-MM-dd" -> Date for a robust delta.
        func delta(_ d: String) -> Int? {
            guard let a = Self.date(today), let b = Self.date(d) else { return nil }
            return Int((b.timeIntervalSince(a) / 86_400).rounded())
        }
        return days.min { l, r in
            let dl = delta(l).map(abs) ?? .max
            let dr = delta(r).map(abs) ?? .max
            if dl != dr { return dl < dr }
            // tie on absolute distance -> the upcoming (later, > today) day wins.
            return l > r
        }
    }

    /// The adjacent day in `days` (which must be sorted ascending) in `direction`,
    /// or nil at the ends (-> the arrow disables).
    static func adjacentDay(from current: String, direction: Direction, in days: [String]) -> String? {
        guard let i = days.firstIndex(of: current) else { return nil }
        switch direction {
        case .prev: return i > 0 ? days[i - 1] : nil
        case .next: return i < days.count - 1 ? days[i + 1] : nil
        }
    }

    /// A display cell for one game. Trailing shows the final score (away–home) when
    /// the game is final AND both scores are present; else the ET tip time parsed
    /// from `gameDateTimeEst`; else the literal "Scheduled" (nil/unparseable tip).
    static func cell(for game: GameDay) -> GameStripCell {
        let away = game.awayTeamId ?? "—"
        let home = game.homeTeamId ?? "—"
        let trailing: String
        if game.status == "final", let a = game.awayScore, let h = game.homeScore {
            trailing = "\(a)\u{2013}\(h)"                 // en dash between away and home
        } else if let et = game.gameDateTimeEst, let tip = tipTimeET(from: et) {
            trailing = tip                                // e.g. "7:30 PM ET"
        } else {
            trailing = "Scheduled"
        }
        return GameStripCell(awayTricode: away, homeTricode: home,
                             awayTeamId: away, homeTeamId: home, trailing: trailing)
    }

    /// PURE ET tip-time formatter: parse an ISO8601 datetime string and render it
    /// in America/New_York as e.g. "7:30 PM ET". Fixed-timezone formatters -> the
    /// output depends only on the input string (no wall-clock). nil when unparseable.
    static func tipTimeET(from iso: String) -> String? {
        guard let d = isoParser.date(from: iso) else { return nil }
        return etTimeFmt.string(from: d) + " ET"
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]     // handles "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()
    private static let etTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "h:mm a"                        // "7:30 PM"
        return f
    }()

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func date(_ s: String) -> Date? { fmt.date(from: s) }
}
