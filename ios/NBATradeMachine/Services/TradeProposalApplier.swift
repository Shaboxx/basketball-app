import Foundation

/// Pure mapping from an `AdvisorProposal` into a `TradeMachineViewModel`.
/// Resolves each move's tricode -> `Team` via the `TeamsViewModel`, seats the
/// participating teams, then applies each move with the team's numeric
/// `teamId` (the form `tradePlayer` expects, matching `TeamTradeTabContent`).
/// The canonical slug is used directly as the `playerId`.
@MainActor
enum TradeProposalApplier {

    /// Applies `proposal` onto `vm`. Returns the set of tricodes that could not
    /// be resolved in `teamsVM` (empty == fully applied). Moves whose teams both
    /// resolve are applied; a move with an unresolvable team is skipped.
    @discardableResult
    static func apply(_ proposal: AdvisorProposal,
                      to vm: TradeMachineViewModel,
                      using teamsVM: TeamsViewModel) -> [String] {
        var teamByTricode: [String: Team] = [:]
        var unresolved: [String] = []
        let mentioned = proposal.moves.flatMap { [$0.fromTeam, $0.toTeam] }
        for tricode in mentioned where teamByTricode[tricode] == nil {
            if let team = teamsVM.teams.first(where: { $0.tricode == tricode }) {
                teamByTricode[tricode] = team
            } else if !unresolved.contains(tricode) {
                unresolved.append(tricode)
            }
        }

        var seatedIds = Set<String>()
        var seated: [Team] = []
        for tricode in mentioned {
            guard let team = teamByTricode[tricode], !seatedIds.contains(team.teamId) else { continue }
            seatedIds.insert(team.teamId)
            seated.append(team)
        }
        vm.setTeams(seated)

        for move in proposal.moves {
            guard let from = teamByTricode[move.fromTeam],
                  let to = teamByTricode[move.toTeam] else { continue }
            vm.tradePlayer(move.playerId, from: from.teamId, to: to.teamId)
        }

        return unresolved
    }
}
