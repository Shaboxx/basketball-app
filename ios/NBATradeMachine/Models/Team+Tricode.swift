import Foundation
extension Team {
    /// NBA-stats numeric teamId -> 3-letter tricode (matches the Python team_map / upload byTeam keys).
    /// Falls back to a derived <=3-char uppercase abbreviation from the team name when the id is
    /// not in the lookup table — never returns the raw numeric teamId as display copy.
    var tricode: String {
        // The Firestore team docs are keyed by tricode, so `teamId` is normally the
        // 2–3-letter code already (e.g. "SAS"). Return it directly so this matches
        // the abbreviation the Teams grid shows; the numeric-id lookup below only
        // applies to any legacy numeric ids that still flow through.
        let id = teamId.trimmingCharacters(in: .whitespaces)
        if (2...3).contains(id.count), id.allSatisfy({ $0.isLetter }) {
            return id.uppercased()
        }
        if let known = Team._tricodeByTeamId[teamId] { return known }
        // Derive up to 3-char uppercase abbreviation from the short team name (e.g. "Warriors").
        let words = name.split(separator: " ").map { String($0) }
        if words.count >= 3 {
            return String(words.prefix(3).compactMap { $0.first }).uppercased()
        } else if words.count == 2 {
            let first  = String(words[0].prefix(2))
            let second = String(words[1].prefix(1))
            return (first + second).uppercased()
        } else {
            return String(name.prefix(3)).uppercased()
        }
    }

    static let _tricodeByTeamId: [String: String] = [
        "1610612737":"ATL","1610612738":"BOS","1610612739":"CLE","1610612740":"NOP",
        "1610612741":"CHI","1610612742":"DAL","1610612743":"DEN","1610612744":"GSW",
        "1610612745":"HOU","1610612746":"LAC","1610612747":"LAL","1610612748":"MIA",
        "1610612749":"MIL","1610612750":"MIN","1610612751":"BKN","1610612752":"NYK",
        "1610612753":"ORL","1610612754":"IND","1610612755":"PHI","1610612756":"PHX",
        "1610612757":"POR","1610612758":"SAC","1610612759":"SAS","1610612760":"OKC",
        "1610612761":"TOR","1610612762":"UTA","1610612763":"MEM","1610612764":"WAS",
        "1610612765":"DET","1610612766":"CHA",
    ]
}
