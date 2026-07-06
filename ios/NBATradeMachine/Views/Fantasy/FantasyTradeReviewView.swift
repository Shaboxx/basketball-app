import SwiftUI

/// The commissioner's trade hub for one league: propose new trades and review the
/// league's proposals. Pending trades carry contextual actions (Accept/Reject/
/// Cancel while proposed; Execute/Veto once accepted); terminal trades show a
/// status badge. Executing re-validates against current rosters and swaps the
/// players. Tapping a trade opens the full both-side swing detail.
struct FantasyTradeReviewView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID

    @State private var showPropose = false
    @State private var detailTrade: FantasyTrade?
    @State private var executeError: String?
    @State private var toast: ToastMessage?

    // MARK: Derived
    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }
    private var format: FantasyFormat {
        league?.rules.effectiveFormat(appDefault: appSettings.fantasyFormat) ?? appSettings.fantasyFormat
    }
    private var trades: [FantasyTrade] { fantasyTradeStore.trades(for: leagueId) }
    private var pending: [FantasyTrade] { trades.filter { !$0.status.isTerminal } }
    private var history: [FantasyTrade] { trades.filter { $0.status.isTerminal } }
    private var hasTwoTeams: Bool { (league?.teamIds.compactMap { fantasyTeamStore.team($0) }.count ?? 0) >= 2 }

    private func teamName(_ id: UUID) -> String { fantasyTeamStore.team(id)?.name ?? "Removed team" }
    private func playerName(_ slug: String) -> String {
        teamsVM.allRosteredPlayers.first { FantasyValueStore.canonicalSlug($0.slug) == slug }?.name ?? slug
    }
    private func names(_ slugs: [String]) -> String {
        slugs.map(playerName).joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPropose = true
                    } label: {
                        Label("Propose Trade", systemImage: "plus.circle")
                    }
                    .disabled(!hasTwoTeams)
                    if !hasTwoTeams {
                        Text("Add at least two teams to the league to trade.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !pending.isEmpty {
                    Section("Pending") { ForEach(pending) { tradeRow($0) } }
                }
                if !history.isEmpty {
                    Section("History") { ForEach(history) { tradeRow($0) } }
                }
                if trades.isEmpty {
                    Section { Text("No trades yet.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Trades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPropose) {
                FantasyProposeTradeView(leagueId: leagueId, onProposed: { name in
                    toast = .success("Trade proposed to \(name)")
                })
                    .environmentObject(fantasyLeagueStore)
                    .environmentObject(fantasyTeamStore)
                    .environmentObject(fantasyTradeStore)
                    .environmentObject(fantasyStore)
                    .environmentObject(teamsVM)
                    .environmentObject(appSettings)
            }
            .sheet(item: $detailTrade) { t in
                tradeDetail(t)
            }
            .alert("Trade can't be executed",
                   isPresented: Binding(get: { executeError != nil }, set: { if !$0 { executeError = nil } })) {
                Button("OK", role: .cancel) { executeError = nil }
            } message: {
                Text(executeError ?? "")
            }
            .toast($toast)
        }
    }

    // MARK: Row

    @ViewBuilder
    private func tradeRow(_ t: FantasyTrade) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // ONLY the informational block opens the detail — the action buttons
            // below sit outside this gesture so an Accept/Execute tap can never
            // also fire the row's tap.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(teamName(t.fromTeamId))  ⇄  \(teamName(t.toTeamId))")
                        .font(.subheadline.bold())
                    Spacer()
                    statusBadge(t.status)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(teamName(t.fromTeamId)) sends: \(names(t.fromSlugs))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(teamName(t.toTeamId)) sends: \(names(t.toSlugs))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { detailTrade = t }
            // Make the two-step model legible: accepting only flips status; Execute
            // is what actually swaps the rosters.
            if t.status == .accepted {
                Text("Accepted — tap Execute to apply to rosters.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            actionRow(t)
        }
    }

    @ViewBuilder
    private func actionRow(_ t: FantasyTrade) -> some View {
        HStack(spacing: 8) {
            switch t.status {
            case .proposed:
                actionButton("Accept", .green) { fantasyTradeStore.accept(t.id) }
                actionButton("Reject", .red) { fantasyTradeStore.reject(t.id) }
                actionButton("Cancel", .secondary) { fantasyTradeStore.cancel(t.id) }
            case .accepted:
                actionButton("Execute", .green) {
                    if let err = fantasyTradeStore.execute(t.id, teamStore: fantasyTeamStore) {
                        executeError = message(for: err)
                    }
                }
                actionButton("Veto", .red) { fantasyTradeStore.veto(t.id) }
            default:
                EmptyView()
            }
        }
        .padding(.top, 2)
    }

    private func actionButton(_ label: String, _ tint: Color, _ act: @escaping () -> Void) -> some View {
        Button(label, action: act)
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(tint)
    }

    @ViewBuilder
    private func statusBadge(_ status: FantasyTradeStatus) -> some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(badgeColor(status).opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: FantasyTradeStatus) -> Color {
        switch status {
        case .executed:            return .green
        case .rejected, .vetoed, .cancelled: return .red
        case .proposed:            return .accentColor
        case .accepted:            return .orange
        }
    }

    private func message(for err: FantasyTradeStore.ExecuteError) -> String {
        switch err {
        case .notFound:     return "This trade no longer exists."
        case .notAccepted:  return "Only an accepted trade can be executed."
        case .invalidNow:   return "A player in this trade has since moved teams. Cancel and re-propose."
        }
    }

    // MARK: Detail

    private func resolve(_ slugs: [String]) -> [FantasyValue] { slugs.compactMap { fantasyStore.value(for: $0) } }

    /// Over-limit advisory for one side of a pending trade (nil if it fits / team gone).
    private func rosterNote(teamId: UUID, sends: [String], receives: [String]) -> String? {
        guard let team = fantasyTeamStore.team(teamId) else { return nil }
        return FantasyRosterAdvisory.overLimitNote(
            teamName: team.name, current: team.playerSlugs, sends: sends, receives: receives,
            limits: fantasyLeagueStore.effectiveLimits(for: teamId, appWide: appSettings.fantasyRosterLimits))
    }

    private func swing(sender: UUID, sends: [String], receives: [String]) -> FantasyTradeSwing {
        // Profile must reflect the PRE-trade roster ("addresses a weakness" vs
        // "adds to a strength"). For an executed trade the current roster is
        // already post-swap, so reverse it (remove received, add back sent); for
        // a pending trade this is a no-op.
        let current = fantasyTeamStore.team(sender)?.playerSlugs ?? []
        let preTrade = FantasyTradeEngine.resultingRoster(current: current, removing: receives, adding: sends)
        return FantasyTradeMath.swing(
            incoming: resolve(receives), outgoing: resolve(sends),
            teamProfile: FantasyTeamProfile.categoryTotals(resolve(preTrade)),
            meta: fantasyStore.meta, format: format, dynastyOn: appSettings.dynastyOn)
    }

    @ViewBuilder
    private func tradeDetail(_ t: FantasyTrade) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FantasyTradeVerdictCard(
                        title: teamName(t.fromTeamId),
                        swing: swing(sender: t.fromTeamId, sends: t.fromSlugs, receives: t.toSlugs),
                        format: format)
                    FantasyTradeVerdictCard(
                        title: teamName(t.toTeamId),
                        swing: swing(sender: t.toTeamId, sends: t.toSlugs, receives: t.fromSlugs),
                        format: format)
                    // Advisory only for a not-yet-applied trade (an executed roster is
                    // already post-swap, so re-applying sends/receives would be wrong).
                    if !t.status.isTerminal {
                        if let note = rosterNote(teamId: t.fromTeamId, sends: t.fromSlugs, receives: t.toSlugs) {
                            RosterAdvisoryRow(note: note)
                        }
                        if let note = rosterNote(teamId: t.toTeamId, sends: t.toSlugs, receives: t.fromSlugs) {
                            RosterAdvisoryRow(note: note)
                        }
                    }
                    if !t.note.isEmpty {
                        Text("“\(t.note)”").font(.caption).italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Trade Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { detailTrade = nil } }
            }
        }
    }
}
