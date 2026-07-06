import Foundation

/// Non-blocking legality advisory for a fantasy trade: fantasy trades are about
/// roster construction, but the trade engine only validates ownership/emptiness,
/// so a count-changing swap (e.g. 3-for-1) can leave a team over its roster-size
/// limit — which the rest of the app otherwise enforces. This computes a plain
/// advisory string per side so the verdict surfaces can warn at trade time.
/// Pure + `nonisolated` so it's unit-testable and callable from any view.
nonisolated enum FantasyRosterAdvisory {

    /// A warning if applying the trade would leave `teamName` over its total roster
    /// limit; nil when the resulting roster fits. `sends` are the players the team
    /// gives up, `receives` the players it takes back.
    static func overLimitNote(teamName: String,
                              current: [String],
                              sends: [String],
                              receives: [String],
                              limits: FantasyRosterLimits) -> String? {
        let resulting = FantasyTradeEngine.resultingRoster(current: current, removing: sends, adding: receives)
        guard resulting.count > limits.total else { return nil }
        let over = resulting.count - limits.total
        return "\(teamName) would carry \(resulting.count) players — \(over) over its \(limits.total)-player limit."
    }
}
