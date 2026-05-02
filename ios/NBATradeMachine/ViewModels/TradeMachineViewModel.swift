import Foundation
import Combine

@MainActor
final class TradeMachineViewModel: ObservableObject {
    static let maxTeams = 6

    @Published var trade = Trade()
    @Published var validation: TradeValidation?
    @Published var fitWarnings: [PositionFitWarning] = []
    @Published var alertMessage: String?
    @Published var isOffseason: Bool = false {
        didSet {
            guard isOffseason != oldValue else { return }
            pruneSelectionsForActiveYear()
            validation = nil
            fitWarnings = []
            alertMessage = nil
        }
    }

    private weak var teamsVM: TeamsViewModel?
    private weak var rulesVM: LeagueRulesViewModel?
    private var cancellables = Set<AnyCancellable>()

    var activeYearOffset: Int { isOffseason ? 1 : 0 }

    func configure(teamsVM: TeamsViewModel, rulesVM: LeagueRulesViewModel) {
        guard self.teamsVM !== teamsVM || self.rulesVM !== rulesVM else { return }
        self.teamsVM = teamsVM
        self.rulesVM = rulesVM
        cancellables.removeAll()
        teamsVM.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        rulesVM.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        objectWillChange.send()
    }

    var allTeams: [Team] { teamsVM?.teams ?? [] }

    var availableTeamsToAdd: [Team] {
        let used = trade.teamIds
        return allTeams.filter { !used.contains($0.teamId) }
    }

    func setInitialTeams(_ a: Team, _ b: Team) {
        trade.teams = [a, b]
        trade.movements.removeAll()
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func addTeam(_ team: Team) {
        guard trade.teams.count < Self.maxTeams,
              !trade.teamIds.contains(team.teamId) else { return }
        trade.teams.append(team)
    }

    func tradePlayer(_ playerId: String, from fromTeamId: String, to toTeamId: String) {
        trade.movements.removeAll { $0.playerId == playerId }
        trade.movements.append(PlayerMovement(playerId: playerId, fromTeamId: fromTeamId, toTeamId: toTeamId))
        validation = nil
        alertMessage = nil
    }

    func untradePlayer(_ playerId: String) {
        trade.movements.removeAll { $0.playerId == playerId }
        validation = nil
        alertMessage = nil
    }

    func roster(for teamId: String) -> [Player] {
        let outgoing = Set(trade.outgoingPlayerIds(from: teamId))
        let all = teamsVM?.players(for: teamId) ?? []
        return all.filter { p in
            p.salary(forSeasonOffset: activeYearOffset) > 0 && !outgoing.contains(p.id)
        }
    }

    func incomingPlayers(to teamId: String) -> [Player] {
        var result: [Player] = []
        for movement in trade.movements where movement.toTeamId == teamId {
            if let player = teamsVM?.players(for: movement.fromTeamId).first(where: { $0.id == movement.playerId }) {
                result.append(player)
            }
        }
        return result
    }

    func outgoingPlayers(from teamId: String) -> [Player] {
        let ids = Set(trade.outgoingPlayerIds(from: teamId))
        let all = teamsVM?.players(for: teamId) ?? []
        return all.filter { ids.contains($0.id) }
    }

    func teamTotalSalary(for teamId: String) -> Int {
        let players = teamsVM?.players(for: teamId) ?? []
        return players.reduce(0) { $0 + $1.salary(forSeasonOffset: activeYearOffset) }
    }

    func outgoingSalary(from teamId: String) -> Int {
        outgoingPlayers(from: teamId).reduce(0) { $0 + $1.salary(forSeasonOffset: activeYearOffset) }
    }

    func incomingSalary(to teamId: String) -> Int {
        incomingPlayers(to: teamId).reduce(0) { $0 + $1.salary(forSeasonOffset: activeYearOffset) }
    }

    func postTradeTotal(for teamId: String) -> Int {
        teamTotalSalary(for: teamId) - outgoingSalary(from: teamId) + incomingSalary(to: teamId)
    }

    func capTier(for teamId: String) -> LeagueRules.CapTier? {
        guard let rules = rulesVM?.rules else { return nil }
        return rules.tier(for: postTradeTotal(for: teamId))
    }

    func validate() {
        let flows = trade.teams.map {
            TradeAnalyzer.TeamFlow(
                teamId: $0.teamId,
                teamName: $0.fullName,
                outgoing: outgoingSalary(from: $0.teamId),
                incoming: incomingSalary(to: $0.teamId)
            )
        }
        validation = TradeAnalyzer.validate(flows: flows)

        var warnings: [PositionFitWarning] = []
        for team in trade.teams {
            warnings += TradeAnalyzer.fitWarnings(
                incoming: incomingPlayers(to: team.teamId),
                receivingRoster: roster(for: team.teamId),
                teamId: team.teamId
            )
        }
        fitWarnings = warnings
        alertMessage = buildAlertMessage()
    }

    private func buildAlertMessage() -> String? {
        var sections: [String] = []
        if let v = validation, !v.isValid {
            sections.append("Trade is invalid:\n\(v.reason)")
        }
        if let capLines = buildCapWarningLines(), !capLines.isEmpty {
            sections.append("This trade pushes a team into a worse cap tier:\n" + capLines.joined(separator: "\n"))
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private func buildCapWarningLines() -> [String]? {
        guard let rules = rulesVM?.rules else { return nil }
        var lines: [String] = []
        for team in trade.teams {
            let current = rules.tier(for: teamTotalSalary(for: team.teamId))
            let post = rules.tier(for: postTradeTotal(for: team.teamId))
            if post > current {
                lines.append("\(team.fullName): \(current.rawValue) -> \(post.rawValue)")
            }
        }
        return lines
    }

    func reset() {
        trade.reset()
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    private func pruneSelectionsForActiveYear() {
        let offset = activeYearOffset
        trade.movements.removeAll { movement in
            guard let players = teamsVM?.players(for: movement.fromTeamId),
                  let player = players.first(where: { $0.id == movement.playerId }) else {
                return true
            }
            return player.salary(forSeasonOffset: offset) <= 0
        }
    }
}
