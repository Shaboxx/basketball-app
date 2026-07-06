import SwiftUI

/// Propose a trade between two teams IN a league (commissioner slice). Pick the
/// two teams, toggle which players each sends, see the live symmetric swing for
/// both, then propose — creating a `.proposed` trade the recipient can accept and
/// the commissioner can execute. Pure math via FantasyTradeMath.
struct FantasyProposeTradeView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyTradeStore: FantasyTradeStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID
    /// Called with the receiver's team name after a successful propose, so the
    /// presenter can confirm the (otherwise silent) dismiss with a toast.
    var onProposed: (String) -> Void = { _ in }

    @State private var fromTeamId: UUID?
    @State private var toTeamId: UUID?
    @State private var fromSlugs: [String] = []       // proposer SENDS (canonical)
    @State private var toSlugs: [String] = []         // recipient SENDS (canonical)

    // MARK: Derived
    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }
    private var format: FantasyFormat {
        league?.rules.effectiveFormat(appDefault: appSettings.fantasyFormat) ?? appSettings.fantasyFormat
    }
    private var memberTeams: [FantasyTeam] {
        (league?.teamIds ?? []).compactMap { fantasyTeamStore.team($0) }
    }
    private var fromTeam: FantasyTeam? { fromTeamId.flatMap { fantasyTeamStore.team($0) } }
    private var toTeam: FantasyTeam? { toTeamId.flatMap { fantasyTeamStore.team($0) } }

    private var playerBySlug: [String: Player] { teamsVM.playerByCanonicalSlug }   // cached in the VM
    private func resolve(_ slugs: [String]) -> [FantasyValue] {
        slugs.compactMap { fantasyStore.value(for: $0) }
    }

    private var fromSwing: FantasyTradeSwing? {
        guard let from = fromTeam else { return nil }
        return FantasyTradeMath.swing(
            incoming: resolve(toSlugs), outgoing: resolve(fromSlugs),
            teamProfile: FantasyTeamProfile.categoryTotals(resolve(from.playerSlugs)),
            meta: fantasyStore.meta, format: format, dynastyOn: appSettings.dynastyOn)
    }
    private var toSwing: FantasyTradeSwing? {
        guard let to = toTeam else { return nil }
        return FantasyTradeMath.swing(
            incoming: resolve(fromSlugs), outgoing: resolve(toSlugs),
            teamProfile: FantasyTeamProfile.categoryTotals(resolve(to.playerSlugs)),
            meta: fantasyStore.meta, format: format, dynastyOn: appSettings.dynastyOn)
    }

    private var canPropose: Bool {
        guard let f = fromTeamId, let t = toTeamId else { return false }
        return FantasyTradeEngine.isValid(
            fromTeamId: f, toTeamId: t, fromSlugs: fromSlugs, toSlugs: toSlugs,
            fromRoster: fromTeam?.playerSlugs ?? [], toRoster: toTeam?.playerSlugs ?? [])
    }

    var body: some View {
        NavigationStack {
            Group {
                if memberTeams.count < 2 {
                    ContentUnavailableView("Add at least two teams",
                        systemImage: "person.2.slash",
                        description: Text("A league needs two teams before you can propose a trade."))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            teamPickers
                            if fromTeam != nil { sidePanel(team: fromTeam!, sending: $fromSlugs, title: "Proposer sends") }
                            if toTeam != nil { sidePanel(team: toTeam!, sending: $toSlugs, title: "Receiver sends") }
                            verdicts
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Propose Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") {
                        fantasyTradeStore.propose(
                            leagueId: leagueId, fromTeamId: fromTeamId!, toTeamId: toTeamId!,
                            fromSlugs: fromSlugs, toSlugs: toSlugs)
                        onProposed(toTeam?.name ?? "the other team")
                        dismiss()
                    }
                    .disabled(!canPropose)
                }
            }
            .onAppear(perform: seedTeams)
        }
    }

    private func seedTeams() {
        // Default the proposer to My Team if it's in this league, else the first member.
        if fromTeamId == nil {
            let my = fantasyTeamStore.myTeamId
            fromTeamId = memberTeams.first { $0.id == my }?.id ?? memberTeams.first?.id
        }
        if toTeamId == nil {
            toTeamId = memberTeams.first { $0.id != fromTeamId }?.id
        }
    }

    // MARK: Pickers

    @ViewBuilder private var teamPickers: some View {
        VStack(spacing: 10) {
            teamMenu("From (proposer)", selection: $fromTeamId, exclude: toTeamId) { fromSlugs = [] }
            teamMenu("To (receiver)", selection: $toTeamId, exclude: fromTeamId) { toSlugs = [] }
        }
    }

    @ViewBuilder
    private func teamMenu(_ label: String, selection: Binding<UUID?>,
                          exclude: UUID?, onChange: @escaping () -> Void) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(memberTeams.filter { $0.id != exclude }) { team in
                    Button(team.name) {
                        selection.wrappedValue = team.id
                        onChange()
                    }
                }
            } label: {
                Label(fantasyTeamStore.team(selection.wrappedValue ?? UUID())?.name ?? "Pick",
                      systemImage: "chevron.up.chevron.down").font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Roster side panel

    @ViewBuilder
    private func sidePanel(team: FantasyTeam, sending: Binding<[String]>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(team.name) — \(title)").font(.headline)
            if team.playerSlugs.isEmpty {
                Text("This team has no players.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(team.playerSlugs, id: \.self) { slug in
                    sendRow(slug, sending: sending)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sendRow(_ slug: String, sending: Binding<[String]>) -> some View {
        let canon = FantasyValueStore.canonicalSlug(slug)
        let isSending = sending.wrappedValue.contains(canon)
        Button {
            if isSending { sending.wrappedValue.removeAll { $0 == canon } }
            else { sending.wrappedValue.append(canon) }
        } label: {
            HStack(spacing: 10) {
                HeadshotImage(slug: playerBySlug[canon]?.slug ?? slug, size: 34)
                Text(playerBySlug[canon]?.name ?? slug).font(.subheadline).lineLimit(1)
                Spacer(minLength: 4)
                if let fv = fantasyStore.value(for: canon) {
                    Text(String(format: "%.1f", format.entry(in: fv).value))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: isSending ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSending ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Verdicts

    @ViewBuilder private var verdicts: some View {
        if let fs = fromSwing, let ts = toSwing, !fromSlugs.isEmpty || !toSlugs.isEmpty {
            FantasyTradeVerdictCard(title: fromTeam?.name ?? "Proposer", swing: fs, format: format)
            FantasyTradeVerdictCard(title: toTeam?.name ?? "Receiver", swing: ts, format: format)
        }
        if fromSlugs.isEmpty || toSlugs.isEmpty {
            Text("Each side must send at least one player.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
