import Foundation
import Combine

@MainActor
final class TradeMachineViewModel: ObservableObject {
    static let maxTeams = 6
    private static let historyLimit = 50

    struct HistoryEntry: Identifiable {
        let id = UUID()
        let label: String
        let trade: Trade
        let isOffseason: Bool
    }

    @Published var trade = Trade()
    @Published var validation: TradeValidation?
    @Published var fitWarnings: [PositionFitWarning] = []
    @Published var alertMessage: String?
    @Published private(set) var history: [HistoryEntry] = []

    @Published var isOffseason: Bool = false {
        willSet {
            if newValue != isOffseason && !isApplyingHistory {
                recordHistory(newValue ? "Enable offseason mode" : "Disable offseason mode")
            }
        }
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
    private var isApplyingHistory = false

    var activeYearOffset: Int { isOffseason ? 1 : 0 }
    var canUndo: Bool { !history.isEmpty }

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
        recordHistory("Start trade: \(a.teamId) and \(b.teamId)")
        trade.teams = [a, b]
        trade.movements.removeAll()
        trade.cashSent.removeAll()
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func addTeam(_ team: Team) {
        guard trade.teams.count < Self.maxTeams,
              !trade.teamIds.contains(team.teamId) else { return }
        recordHistory("Add \(team.teamId)")
        trade.teams.append(team)
    }

    func tradePlayer(_ playerId: String, from fromTeamId: String, to toTeamId: String) {
        let name = playerName(playerId, hint: fromTeamId)
        recordHistory("Move \(name): \(fromTeamId) -> \(toTeamId)")
        trade.movements.removeAll { $0.playerId == playerId }
        trade.movements.append(PlayerMovement(playerId: playerId, fromTeamId: fromTeamId, toTeamId: toTeamId))
        validation = nil
        alertMessage = nil
    }

    func untradePlayer(_ playerId: String) {
        let name = playerName(playerId, hint: nil)
        recordHistory("Cancel \(name)'s move")
        trade.movements.removeAll { $0.playerId == playerId }
        validation = nil
        alertMessage = nil
    }

    func addPickMovement(_ pick: Pick, from fromTeamId: String, to toTeamId: String) {
        guard fromTeamId != toTeamId,
              trade.teamIds.contains(fromTeamId),
              trade.teamIds.contains(toTeamId) else { return }
        recordHistory("Move \(pick.shortLabel): \(fromTeamId) -> \(toTeamId)")
        trade.pickMovements.append(PickMovement(pick: pick, fromTeamId: fromTeamId, toTeamId: toTeamId))
        validation = nil
        alertMessage = nil
    }

    func removePickMovement(_ movementId: PickMovement.ID) {
        guard let movement = trade.pickMovements.first(where: { $0.id == movementId }) else { return }
        recordHistory("Cancel \(movement.pick.shortLabel)")
        trade.pickMovements.removeAll { $0.id == movementId }
        validation = nil
        alertMessage = nil
    }

    func setCash(_ amount: Int, from teamId: String) {
        let clean = max(0, amount)
        let current = trade.cash(from: teamId)
        guard clean != current else { return }
        let display = clean > 0 ? Money.display(clean) : "$0"
        recordHistory("\(teamId) cash: \(display)")
        if clean == 0 {
            trade.cashSent.removeValue(forKey: teamId)
        } else {
            trade.cashSent[teamId] = clean
        }
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
        if let cashLines = buildCashWarningLines(), !cashLines.isEmpty {
            sections.append("Cash limit warning:\n" + cashLines.joined(separator: "\n"))
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

    private func buildCashWarningLines() -> [String]? {
        var lines: [String] = []
        for team in trade.teams {
            let amount = trade.cash(from: team.teamId)
            if amount > Trade.cashLimit {
                lines.append("\(team.fullName) sending \(Money.display(amount)) (over $8.12M season limit)")
            }
        }
        return lines.isEmpty ? nil : lines
    }

    func reset() {
        recordHistory("Reset trade")
        trade.reset()
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func undo() {
        guard let last = history.popLast() else { return }
        isApplyingHistory = true
        trade = last.trade
        if isOffseason != last.isOffseason {
            isOffseason = last.isOffseason
        }
        isApplyingHistory = false
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func undoTo(entryId: HistoryEntry.ID) {
        guard let idx = history.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = history[idx]
        history.removeSubrange(idx...)
        isApplyingHistory = true
        trade = entry.trade
        if isOffseason != entry.isOffseason {
            isOffseason = entry.isOffseason
        }
        isApplyingHistory = false
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func clearHistory() {
        history.removeAll()
    }

    private func recordHistory(_ label: String) {
        guard !isApplyingHistory else { return }
        history.append(HistoryEntry(label: label, trade: trade, isOffseason: isOffseason))
        if history.count > Self.historyLimit { history.removeFirst() }
    }

    private func playerName(_ playerId: String, hint: String?) -> String {
        let teamIds = (hint.map { [$0] } ?? []) + trade.teams.map(\.teamId)
        for tid in teamIds {
            if let p = teamsVM?.players(for: tid).first(where: { $0.id == playerId }) {
                return p.name
            }
        }
        return "player"
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
