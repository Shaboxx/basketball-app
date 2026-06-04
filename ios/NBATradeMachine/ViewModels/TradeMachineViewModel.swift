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
        var exceptionUsed: ExceptionType = .capSpace   // M2: cap exception used
        var isSignAndTrade: Bool = false               // M3
        var priorTeamId: String? = nil                 // M3: FA's prior team (must be a trade participant)
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
        picksVM.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        objectWillChange.send()
    }

    var allTeams: [Team] { teamsVM?.teams ?? [] }

    /// True when the machine holds user work that applying an Advisor proposal
    /// would overwrite (in-flight moves, waives, or offseason signings/draftees).
    var hasUncommittedWork: Bool {
        !trade.movements.isEmpty || !trade.waived.isEmpty
            || !signedContracts.isEmpty || !signedFreeAgents.isEmpty || !draftedProspects.isEmpty
    }

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

    /// Seed the machine with a pre-selected set of teams (from the Teams-grid
    /// selection mode) so it opens straight into `activeTradeView`. Resets all
    /// prior state, then installs up to `maxTeams` teams and clears validation,
    /// fit warnings, and any pending alert.
    func setTeams(_ teams: [Team]) {
        reset()
        trade.teams = Array(teams.prefix(Self.maxTeams))
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

    // MARK: - Waive / Dismiss

    /// Waive an active player. Their guaranteed salary stays on the cap as
    /// dead money (`teamTotalSalary` is unchanged because it sums over the
    /// full team list), but they leave the tradeable `roster(for:)`.
    func waivePlayer(_ player: Player, from teamId: String) {
        recordHistory("Waive \(player.name)")
        // A waived player can't also be in flight.
        trade.movements.removeAll { $0.playerId == player.id }
        trade.waived.removeAll { $0.playerId == player.id }
        trade.waived.append(WaivedContract(
            playerId: player.id,
            teamId: teamId,
            salary: effectiveSalary(for: player),
            yearsRemaining: max(0, player.contractYearsRemaining(from: activeYearOffset))
        ))
        validation = nil
        alertMessage = nil
    }

    func unwaivePlayer(_ playerId: String) {
        let name = playerName(playerId, hint: nil)
        recordHistory("Un-waive \(name)")
        trade.waived.removeAll { $0.playerId == playerId }
        validation = nil
        alertMessage = nil
    }

    /// Dismiss an expired (offseason) player — they leave the roster entirely
    /// and carry NO dead money (their contract already lapsed). Also tears
    /// down any in-flight re-sign override for them.
    func dismissPlayer(_ player: Player, from teamId: String) {
        recordHistory("Dismiss \(player.name)")
        trade.movements.removeAll { $0.playerId == player.id }
        signedContracts.removeValue(forKey: player.id)
        trade.dismissed.removeAll { $0.playerId == player.id }
        trade.dismissed.append(DismissedPlayer(playerId: player.id, teamId: teamId))
        validation = nil
        alertMessage = nil
    }

    func undismissPlayer(_ playerId: String) {
        let name = playerName(playerId, hint: nil)
        recordHistory("Restore \(name)")
        trade.dismissed.removeAll { $0.playerId == playerId }
        validation = nil
        alertMessage = nil
    }

    func isWaived(_ id: String) -> Bool {
        trade.waived.contains { $0.playerId == id }
    }

    func isDismissed(_ id: String) -> Bool {
        trade.dismissed.contains { $0.playerId == id }
    }

    /// Waived players for a team, resolved against the loaded roster and in
    /// waive order.
    func waivedPlayers(for teamId: String) -> [Player] {
        let all = teamsVM?.players(for: teamId) ?? []
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return trade.waived
            .filter { $0.teamId == teamId }
            .compactMap { byId[$0.playerId] }
    }

    /// Dismissed players for a team, resolved against the loaded roster and in
    /// dismiss order.
    func dismissedPlayers(for teamId: String) -> [Player] {
        let all = teamsVM?.players(for: teamId) ?? []
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return trade.dismissed
            .filter { $0.teamId == teamId }
            .compactMap { byId[$0.playerId] }
    }

    /// Total dead money charged to a team from waived players.
    func deadMoney(for teamId: String) -> Int {
        trade.waived
            .filter { $0.teamId == teamId }
            .reduce(0) { $0 + deadMoneyHit($1) }
    }

    /// The single place a future stretch calc will branch.
    private func deadMoneyHit(_ w: WaivedContract) -> Int {
        // TODO: stretch — when w.stretch, spread w.salary over (2*w.yearsRemaining)+1.
        w.salary
    }

    // MARK: - Team removal

    var canRemoveTeam: Bool { trade.teams.count > 2 }

    /// Remove a team from the trade (only allowed with >2 teams). Drops the
    /// team plus every selection tied to it. Undo restores the snapshot.
    func removeTeam(_ teamId: String) {
        guard trade.teams.count > 2, trade.teamIds.contains(teamId) else { return }
        let name = trade.teams.first { $0.teamId == teamId }?.fullName ?? teamId
        recordHistory("Remove \(name)")
        let rosterIds = Set((teamsVM?.players(for: teamId) ?? []).map(\.id))
        trade.teams.removeAll { $0.teamId == teamId }
        trade.movements.removeAll { $0.fromTeamId == teamId || $0.toTeamId == teamId }
        trade.pickMovements.removeAll { $0.fromTeamId == teamId || $0.toTeamId == teamId }
        trade.cashSent.removeValue(forKey: teamId)
        trade.waived.removeAll { $0.teamId == teamId }
        trade.dismissed.removeAll { $0.teamId == teamId }
        signedFreeAgents.removeValue(forKey: teamId)
        draftedProspects.removeValue(forKey: teamId)
        signedContracts = signedContracts.filter { !rosterIds.contains($0.key) }
        validation = nil
        fitWarnings = []
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
        let released = Set(
            trade.waived.filter { $0.teamId == teamId }.map(\.playerId)
            + trade.dismissed.filter { $0.teamId == teamId }.map(\.playerId)
        )
        let all = teamsVM?.players(for: teamId) ?? []
        return all.filter { p in
            guard !outgoing.contains(p.id) else { return false }
            guard !released.contains(p.id) else { return false }
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
        let issues = complianceIssues()
        let blocks = issues.filter { $0.severity == .block }

        // Keep the existing structural matching from TradeAnalyzer as a baseline
        // (each team must send and receive); compliance blocks supersede it.
        let flows = trade.teams.map {
            TradeAnalyzer.TeamFlow(
                teamId: $0.teamId,
                teamName: $0.fullName,
                outgoing: outgoingSalary(from: $0.teamId),
                incoming: incomingSalary(to: $0.teamId)
            )
        }
        let structural = TradeAnalyzer.validate(flows: flows)

        if !structural.isValid {
            validation = structural
        } else if let firstBlock = blocks.first {
            validation = TradeValidation(isValid: false, reason: firstBlock.message)
        } else {
            validation = TradeValidation(isValid: true, reason: "")
        }

        var warnings: [PositionFitWarning] = []
        for team in trade.teams {
            warnings += TradeAnalyzer.fitWarnings(
                incoming: incomingPlayers(to: team.teamId),
                receivingRoster: roster(for: team.teamId),
                teamId: team.teamId
            )
        }
        fitWarnings = warnings

        alertMessage = buildAlertMessage(issues: issues)
    }

    /// Run the CBA compliance engine for every team in the trade.
    private func complianceIssues() -> [ComplianceIssue] {
        guard rulesVM?.rules != nil else { return [] }
        let contexts = trade.teams.map { teamContext(for: $0) }
        return TradeCompliance.evaluate(teams: contexts)
    }

    /// First-apron hard cap if any in-scenario signing for this team used a
    /// hard-capping exception (sign-and-trade forces `.signAndTrade`, which is
    /// hard-capping); else nil. (M2)
    /// True if any in-scenario signing for this team is a sign-and-trade. (M3)
    private func acquiringViaSignAndTrade(for teamId: String) -> Bool {
        signedFAs(for: teamId).contains { $0.isSignAndTrade }
    }

    private func hardCapLimit(for teamId: String) -> Int? {
        guard let rules = rulesVM?.rules else { return nil }
        let hardCapped = signedFAs(for: teamId).contains { $0.exceptionUsed.hardCapsAtFirstApron }
        return hardCapped ? rules.firstApron : nil
    }

    private func teamContext(for team: Team) -> TeamContext {
        let id = team.teamId
        let incoming = incomingPlayers(to: id).map(contractLite)
        let outgoing = outgoingPlayers(from: id).map(contractLite)
        let postCount = postTradeRosterCount(for: id)
        let tier = capTier(for: id) ?? .underCap
        let horizon = draftYearHorizon()
        return TeamContext(
            teamId: id,
            teamName: team.fullName,
            preTradeSalary: teamTotalSalary(for: id),
            postTradeSalary: postTradeTotal(for: id),
            postTradeTier: tier,
            incoming: incoming,
            outgoing: outgoing,
            cashSent: trade.cash(from: id),
            postTradeRosterCount: postCount,
            isOffseason: isOffseason,
            ownedFirstRoundYears: ownedFirstRoundYears(for: id),
            draftYearHorizon: horizon,
            hardCapLimit: hardCapLimit(for: id),
            acquiringViaSignAndTrade: acquiringViaSignAndTrade(for: id)
        )
    }

    private func contractLite(_ p: Player) -> ContractLite {
        ContractLite(playerId: p.id, name: p.name, salaryY1: p.salaryY1 ?? 0,
                     standardMax: p.standardMax, nextContractMax: p.nextContractMax)
    }

    /// kept roster + incoming + signed FAs + drafted prospects.
    private func postTradeRosterCount(for teamId: String) -> Int {
        roster(for: teamId).count
            + incomingPlayers(to: teamId).count
            + signedFAs(for: teamId).count
            + draftPicks(for: teamId).count
    }

    /// Future draft years with >=1 owned first-round pick AFTER the trade.
    private func ownedFirstRoundYears(for teamId: String) -> Set<Int> {
        var countByYear: [Int: Int] = [:]
        for pick in (picksVM?.picks(for: teamId) ?? []) where pick.round == 1 {
            countByYear[pick.year, default: 0] += 1
        }
        for pm in trade.picksOutgoing(from: teamId) where pm.pick.round == 1 {
            countByYear[pm.pick.year, default: 0] -= 1
        }
        for pm in trade.picksIncoming(to: teamId) where pm.pick.round == 1 {
            countByYear[pm.pick.year, default: 0] += 1
        }
        return Set(countByYear.filter { $0.value > 0 }.map(\.key))
    }

    /// Inclusive span of future draft years to evaluate Stepien over — derived
    /// from the league-wide picks data; falls back to a 7-year window.
    private func draftYearHorizon() -> ClosedRange<Int> {
        let years = (picksVM?.picksByTeamId.values.flatMap { $0 } ?? [])
            .filter { $0.round == 1 }.map(\.year)
        guard let lo = years.min(), let hi = years.max(), lo <= hi else {
            return 2026...2032
        }
        return lo...hi
    }

    private func buildAlertMessage(issues: [ComplianceIssue] = []) -> String? {
        var sections: [String] = []
        let blocks = issues.filter { $0.severity == .block }
        // Show the generic "invalid" header only when there are NO CBA blocks;
        // when blocks exist they are listed in full below, so repeating
        // validation.reason (which mirrors the first block) would duplicate it.
        if blocks.isEmpty, let v = validation, !v.isValid {
            sections.append("Trade is invalid:\n\(v.reason)")
        }
        if !blocks.isEmpty {
            sections.append("CBA violations:\n" + blocks.map { "• \($0.message)" }.joined(separator: "\n"))
        }
        let warns = issues.filter { $0.severity == .warn }
        if !warns.isEmpty {
            sections.append("CBA warnings:\n" + warns.map { "• \($0.message)" }.joined(separator: "\n"))
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
        recordHistory("Cancel trade")
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
