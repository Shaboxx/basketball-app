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
    /// Optional pre-seed used by "Counter": the recipient becomes the proposer with
    /// the original terms, which they then tweak. When `replacingTradeId` is set, a
    /// successful propose marks that original trade `.countered`.
    var initialFromTeamId: UUID? = nil
    var initialToTeamId: UUID? = nil
    var initialFromSlugs: [String] = []
    var initialToSlugs: [String] = []
    var replacingTradeId: UUID? = nil

    @State private var fromTeamId: UUID?
    @State private var toTeamId: UUID?
    @State private var fromSlugs: [String] = []       // proposer SENDS (canonical)
    @State private var toSlugs: [String] = []         // recipient SENDS (canonical)
    @State private var fromAssets: [FantasyTradeAsset] = []   // proposer's picks/FAAB
    @State private var toAssets: [FantasyTradeAsset] = []     // receiver's picks/FAAB
    @State private var assetTarget: AssetTarget?              // drives the add-asset sheet

    /// Which side the add-asset sheet is filling.
    private struct AssetTarget: Identifiable { let id = UUID(); let isProposer: Bool }

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
                            if fromTeam != nil { sidePanel(team: fromTeam!, sending: $fromSlugs, assets: $fromAssets, title: "Proposer sends", isProposer: true) }
                            if toTeam != nil { sidePanel(team: toTeam!, sending: $toSlugs, assets: $toAssets, title: "Receiver sends", isProposer: false) }
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
                    Button(replacingTradeId == nil ? "Propose" : "Send Counter") {
                        fantasyTradeStore.propose(
                            leagueId: leagueId, fromTeamId: fromTeamId!, toTeamId: toTeamId!,
                            fromSlugs: fromSlugs, toSlugs: toSlugs,
                            fromAssets: fromAssets, toAssets: toAssets)
                        if let rid = replacingTradeId { fantasyTradeStore.markCountered(rid) }
                        onProposed(toTeam?.name ?? "the other team")
                        dismiss()
                    }
                    .disabled(!canPropose)
                }
            }
            .onAppear(perform: seedTeams)
            .sheet(item: $assetTarget) { target in
                AddAssetSheet { asset in
                    if target.isProposer { fromAssets.append(asset) } else { toAssets.append(asset) }
                }
            }
        }
    }

    private func seedTeams() {
        // Counter pre-seed: adopt the (swapped) original terms once, then let the user tweak.
        if fromTeamId == nil, let seedFrom = initialFromTeamId {
            fromTeamId = seedFrom
            toTeamId = initialToTeamId
            fromSlugs = initialFromSlugs
            toSlugs = initialToSlugs
            return
        }
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
            teamMenu("From (proposer)", selection: $fromTeamId, exclude: toTeamId) { fromSlugs = []; fromAssets = [] }
            teamMenu("To (receiver)", selection: $toTeamId, exclude: fromTeamId) { toSlugs = []; toAssets = [] }
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
    private func sidePanel(team: FantasyTeam, sending: Binding<[String]>,
                           assets: Binding<[FantasyTradeAsset]>, title: String, isProposer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(team.name) — \(title)").font(.headline)
            if team.playerSlugs.isEmpty {
                Text("This team has no players.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(team.playerSlugs, id: \.self) { slug in
                    sendRow(slug, sending: sending)
                }
            }
            assetEditor(assets: assets, isProposer: isProposer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Draft-pick / FAAB chips for a side, plus an Add entry (picks/FAAB ride along).
    @ViewBuilder
    private func assetEditor(assets: Binding<[FantasyTradeAsset]>, isProposer: Bool) -> some View {
        if !assets.wrappedValue.isEmpty {
            Divider()
            ForEach(assets.wrappedValue) { asset in
                HStack(spacing: 8) {
                    Image(systemName: asset.kind == .pick ? "sportscourt" : "dollarsign.circle")
                        .foregroundStyle(.secondary)
                    Text(asset.display).font(.caption)
                    Spacer()
                    Button {
                        assets.wrappedValue.removeAll { $0.id == asset.id }
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
        }
        Button { assetTarget = AssetTarget(isProposer: isProposer) } label: {
            Label("Add pick / FAAB", systemImage: "plus.circle")
        }
        .font(.caption).padding(.top, 2)
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
            rosterAdvisories
            if !fromAssets.isEmpty || !toAssets.isEmpty {
                Text("Draft picks and FAAB ride along but aren't valued yet.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        if fromSlugs.isEmpty || toSlugs.isEmpty {
            Text("Each side must send at least one player.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Non-blocking warnings if either side would end up over its roster limit.
    @ViewBuilder private var rosterAdvisories: some View {
        if let from = fromTeam,
           let note = FantasyRosterAdvisory.overLimitNote(
            teamName: from.name, current: from.playerSlugs, sends: fromSlugs, receives: toSlugs,
            limits: fantasyLeagueStore.effectiveLimits(for: from.id, appWide: appSettings.fantasyRosterLimits)) {
            RosterAdvisoryRow(note: note)
        }
        if let to = toTeam,
           let note = FantasyRosterAdvisory.overLimitNote(
            teamName: to.name, current: to.playerSlugs, sends: toSlugs, receives: fromSlugs,
            limits: fantasyLeagueStore.effectiveLimits(for: to.id, appWide: appSettings.fantasyRosterLimits)) {
            RosterAdvisoryRow(note: note)
        }
    }
}

/// A tiny form to add one draft pick or FAAB amount to a trade side.
private struct AddAssetSheet: View {
    let onAdd: (FantasyTradeAsset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: FantasyTradeAsset.Kind = .pick
    @State private var year = 2027
    @State private var round = 1
    @State private var amount = 10

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Draft pick").tag(FantasyTradeAsset.Kind.pick)
                    Text("FAAB").tag(FantasyTradeAsset.Kind.faab)
                }
                .pickerStyle(.segmented)
                if kind == .pick {
                    Stepper("Year: \(String(year))", value: $year, in: 2025...2035)
                    Stepper("Round: \(round)", value: $round, in: 1...15)
                } else {
                    Stepper("FAAB: $\(amount)", value: $amount, in: 1...1000, step: 5)
                }
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(kind == .pick ? .pick(year: year, round: round) : .faab(amount))
                        dismiss()
                    }
                }
            }
        }
    }
}
