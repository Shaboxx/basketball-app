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
        let signedContracts: [String: ReSignedContract]
        let signedFreeAgents: [String: [SignedFreeAgent]]
        let draftedProspects: [String: [DraftedProspect]]
    }

    /// Re-signed contract recorded against an expired roster player. Keyed by
    /// the player's `id` on `signedContracts`. The salary applies to the
    /// active offseason year (offset 1) — extension years past that are
    /// out of scope for this offseason flow.
    struct ReSignedContract: Hashable {
        let salary: Int
        let years: Int
    }

    /// Free agent signed during offseason mode. Tracked per team so the
    /// roster surfaces them like real players, with a salary that flows
    /// through `teamTotalSalary`.
    struct SignedFreeAgent: Identifiable, Hashable {
        let id: String              // FA slug — also Player.id surrogate
        let name: String
        let position: String
        let salary: Int
        let years: Int
        let kind: FreeAgentKind     // UFA or RFA at time of signing
    }

    enum FreeAgentKind: String, Codable, Hashable {
        case unrestricted
        case restricted
        var shortLabel: String { self == .unrestricted ? "UFA" : "RFA" }
    }

    /// Prospect drafted during offseason mode. The user can only consume a
    /// pick they own; team-before sim removes prospects ahead of their slot.
    struct DraftedProspect: Identifiable, Hashable {
        let id: String              // prospect slug
        let name: String
        let position: String
        let pickOverall: Int        // overall slot used to sign
        let pickYear: Int
        let pickRound: Int
        let rookieScaleSalary: Int  // best-effort rookie scale, 0 if unknown
    }

    @Published var trade = Trade()
    @Published var validation: TradeValidation?
    @Published var fitWarnings: [PositionFitWarning] = []
    @Published var alertMessage: String?
    @Published private(set) var history: [HistoryEntry] = []

    /// Offseason-only: re-sign overrides keyed by Player.id. When offseason
    /// mode is off these are ignored — `effectiveSalary` collapses back to
    /// the contract table.
    @Published var signedContracts: [String: ReSignedContract] = [:]

    /// Offseason-only: free agents signed by each team. Keyed by teamId.
    @Published var signedFreeAgents: [String: [SignedFreeAgent]] = [:]

    /// Offseason-only: prospects drafted by each team. Keyed by teamId.
    @Published var draftedProspects: [String: [DraftedProspect]] = [:]

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
    private weak var picksVM: PicksViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingHistory = false

    var activeYearOffset: Int { isOffseason ? 1 : 0 }
    var canUndo: Bool { !history.isEmpty }

    func configure(teamsVM: TeamsViewModel, rulesVM: LeagueRulesViewModel, picksVM: PicksViewModel) {
        guard self.teamsVM !== teamsVM || self.rulesVM !== rulesVM || self.picksVM !== picksVM else { return }
        self.teamsVM = teamsVM
        self.rulesVM = rulesVM
        self.picksVM = picksVM
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
            guard !outgoing.contains(p.id) else { return false }
            // Offseason: keep contracts that expired between Y1 and Y2 so
            // the user can re-sign them. Active mode: only Y1 contracts.
            if isOffseason {
                return p.salaryY1 ?? 0 > 0
            }
            return p.salary(forSeasonOffset: activeYearOffset) > 0
        }
    }

    /// True when the player is on roster but their contract has lapsed for
    /// the offseason's active year. Drives the "Expired" badge and the
    /// re-sign tap target. Only meaningful in offseason mode.
    func isExpired(_ player: Player) -> Bool {
        guard isOffseason else { return false }
        if signedContracts[player.id] != nil { return false }
        return player.salary(forSeasonOffset: activeYearOffset) <= 0
    }

    /// Effective salary for a roster player in the active year. Honors
    /// re-sign overrides in offseason mode; in regular mode it's just the
    /// contract table.
    func effectiveSalary(for player: Player) -> Int {
        if isOffseason, let resign = signedContracts[player.id] {
            return resign.salary
        }
        return player.salary(forSeasonOffset: activeYearOffset)
    }

    /// Resolve a loaded `Player` by `id` or `slug` across every team roster.
    /// Returns nil when the player isn't in any loaded roster (e.g. a free
    /// agent whose document isn't loaded). Lets the free-agent signing sheet
    /// reach a player's Phase-7 cost cone, which lives on the `Player`
    /// document — not on the bundled `FreeAgent` record.
    func player(matchingSlugOrId key: String) -> Player? {
        guard let byTeam = teamsVM?.playersByTeamId else { return nil }
        for roster in byTeam.values {
            if let hit = roster.first(where: { $0.id == key || $0.slug == key }) {
                return hit
            }
        }
        return nil
    }

    /// Resolves a re-sign override for a player. nil if none in flight or
    /// offseason mode is off.
    func resignedContract(for playerId: String) -> ReSignedContract? {
        guard isOffseason else { return nil }
        return signedContracts[playerId]
    }

    /// Apply or update a re-sign override against an expired player.
    /// Records history so undo restores the prior contract state.
    func signResignContract(player: Player, salary: Int, years: Int) {
        recordHistory("Re-sign \(player.name) \(Money.display(salary)) × \(years)")
        signedContracts[player.id] = ReSignedContract(salary: salary, years: years)
        validation = nil
        alertMessage = nil
    }

    /// Tear down a re-sign override (e.g. user undoes the deal).
    func cancelResignContract(playerId: String) {
        guard signedContracts[playerId] != nil else { return }
        let name = playerName(playerId, hint: nil)
        recordHistory("Cancel re-sign for \(name)")
        signedContracts.removeValue(forKey: playerId)
        validation = nil
        alertMessage = nil
    }

    /// Free agents this team has signed so far. Used by sheet to dedupe and
    /// by depth chart to fold them into the post-trade roster.
    func signedFAs(for teamId: String) -> [SignedFreeAgent] {
        signedFreeAgents[teamId] ?? []
    }

    func signFreeAgent(_ fa: SignedFreeAgent, to teamId: String) {
        recordHistory("Sign \(fa.name) (\(fa.kind.shortLabel)) → \(teamId): \(Money.display(fa.salary)) × \(fa.years)")
        var list = signedFreeAgents[teamId] ?? []
        list.removeAll { $0.id == fa.id }
        list.append(fa)
        signedFreeAgents[teamId] = list
        validation = nil
        alertMessage = nil
    }

    func cancelFreeAgent(id: String, from teamId: String) {
        guard var list = signedFreeAgents[teamId],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let name = list[idx].name
        list.remove(at: idx)
        recordHistory("Cancel signing \(name) → \(teamId)")
        signedFreeAgents[teamId] = list
        validation = nil
        alertMessage = nil
    }

    /// All FAs (across teams) already claimed. Used by the sheet to gray
    /// out names the user has already used.
    func allSignedFreeAgentIds() -> Set<String> {
        Set(signedFreeAgents.values.flatMap { $0 }.map(\.id))
    }

    func draftPicks(for teamId: String) -> [DraftedProspect] {
        draftedProspects[teamId] ?? []
    }

    func draftProspect(_ prospect: DraftedProspect, to teamId: String) {
        recordHistory("Draft \(prospect.name) (#\(prospect.pickOverall)) → \(teamId)")
        var list = draftedProspects[teamId] ?? []
        list.removeAll { $0.id == prospect.id }
        list.append(prospect)
        draftedProspects[teamId] = list
        validation = nil
        alertMessage = nil
    }

    func cancelDraft(id: String, from teamId: String) {
        guard var list = draftedProspects[teamId],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let name = list[idx].name
        list.remove(at: idx)
        recordHistory("Cancel drafting \(name) → \(teamId)")
        draftedProspects[teamId] = list
        validation = nil
        alertMessage = nil
    }

    func allDraftedProspectIds() -> Set<String> {
        Set(draftedProspects.values.flatMap { $0 }.map(\.id))
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
        let base = players.reduce(0) { $0 + effectiveSalary(for: $1) }
        guard isOffseason else { return base }
        let faSum = (signedFreeAgents[teamId] ?? []).reduce(0) { $0 + $1.salary }
        let draftSum = (draftedProspects[teamId] ?? []).reduce(0) { $0 + $1.rookieScaleSalary }
        return base + faSum + draftSum
    }

    func outgoingSalary(from teamId: String) -> Int {
        outgoingPlayers(from: teamId).reduce(0) { $0 + effectiveSalary(for: $1) }
    }

    func incomingSalary(to teamId: String) -> Int {
        incomingPlayers(to: teamId).reduce(0) { $0 + effectiveSalary(for: $1) }
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
        signedContracts.removeAll()
        signedFreeAgents.removeAll()
        draftedProspects.removeAll()
        validation = nil
        fitWarnings = []
        alertMessage = nil
    }

    func undo() {
        guard let last = history.popLast() else { return }
        isApplyingHistory = true
        trade = last.trade
        signedContracts = last.signedContracts
        signedFreeAgents = last.signedFreeAgents
        draftedProspects = last.draftedProspects
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
        signedContracts = entry.signedContracts
        signedFreeAgents = entry.signedFreeAgents
        draftedProspects = entry.draftedProspects
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
        history.append(HistoryEntry(
            label: label,
            trade: trade,
            isOffseason: isOffseason,
            signedContracts: signedContracts,
            signedFreeAgents: signedFreeAgents,
            draftedProspects: draftedProspects
        ))
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
            // Keep re-signed expired players movable in offseason mode.
            if isOffseason, signedContracts[player.id] != nil { return false }
            return player.salary(forSeasonOffset: offset) <= 0
        }
        // Re-sign overrides, FA signings, and drafts only make sense in
        // offseason mode — drop them when toggling back to regular season
        // so post-trade salary math doesn't double-count phantom assets.
        if !isOffseason {
            signedContracts.removeAll()
            signedFreeAgents.removeAll()
            draftedProspects.removeAll()
        }
    }
}
