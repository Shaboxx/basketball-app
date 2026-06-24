import Foundation

/// The league phase served in `leagueCalendar/current`. `unknown` keeps an
/// unrecognized server value from failing the whole decode.
nonisolated enum LeaguePhase: String, Codable, Equatable {
    case offseason, faMoratorium, draftWindow, preseason, regular, tradeDeadline, playoffs
    case unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = LeaguePhase(rawValue: raw) ?? .unknown
    }
}

/// The single source-of-truth calendar doc (`leagueCalendar/current`), written by
/// scripts/upload_league_calendar.py. `statsSeason` keys leagueNorms; `capSeason`
/// keys leagueRules. Only the fields the app consumes today are decoded (windows
/// are deferred to a later sub-project).
nonisolated struct LeagueCalendar: Codable, Equatable {
    let statsSeason: String
    let capSeason: String
    let phase: LeaguePhase
    let isOffseason: Bool
    let asOfDate: String?
    let dataAsOf: String?
}
