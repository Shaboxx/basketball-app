import SwiftUI

/// Fantasy Trade Machine: My side vs an opponent (a saved team or the free league
/// pool). Assemble incoming/outgoing players; see per-side net value + category
/// swing (or fp/game for points formats) + plain-language flags. No salary/apron —
/// a structural "each side moves ≥1 player" gate only. Pure math via FantasyTradeMath.
struct FantasyTradeMachineView: View {
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var fantasyStore: FantasyValueStore
    @EnvironmentObject var teamsVM: TeamsViewModel
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var myTeamId: UUID?
    @State private var opponentTeamId: UUID?          // nil ⇒ free any-player pool (default)
    @State private var incomingSlugs: [String] = []   // players My side RECEIVES (canonical)
    @State private var outgoingSlugs: [String] = []   // players My side SENDS (from My roster)
    @State private var showAddIncoming = false
    @State private var showMyTeamPicker = false
    @State private var showOpponentPicker = false

    // MARK: Derived

    private var playerBySlug: [String: Player] { teamsVM.playerByCanonicalSlug }   // cached in the VM

    private var myTeam: FantasyTeam? { myTeamId.flatMap { fantasyTeamStore.team($0) } }
    private var opponentTeam: FantasyTeam? { opponentTeamId.flatMap { fantasyTeamStore.team($0) } }
    private var myRosterSlugs: [String] { myTeam?.playerSlugs ?? [] }

    /// The pool the "Add incoming" search draws from: the opponent's roster when a
    /// saved team is chosen, else the whole league pool.
    private var incomingPool: [Player] {
        if let opp = opponentTeam {
            return opp.playerSlugs.compactMap { playerBySlug[FantasyValueStore.canonicalSlug($0)] }
        }
        return teamsVM.allRosteredPlayers
    }

    private func resolve(_ slugs: [String]) -> [FantasyValue] {
        slugs.compactMap { fantasyStore.value(for: $0) }
    }

    private var mySwing: FantasyTradeSwing {
        FantasyTradeMath.swing(
            incoming: resolve(incomingSlugs), outgoing: resolve(outgoingSlugs),
            teamProfile: FantasyTeamProfile.categoryTotals(resolve(myRosterSlugs)),
            meta: fantasyStore.meta, format: appSettings.fantasyFormat, dynastyOn: appSettings.dynastyOn)
    }

    /// Symmetric opponent verdict — only when a SAVED opponent team is chosen.
    private var opponentSwing: FantasyTradeSwing? {
        guard let opp = opponentTeam else { return nil }
        return FantasyTradeMath.swing(
            incoming: resolve(outgoingSlugs), outgoing: resolve(incomingSlugs),   // swapped
            teamProfile: FantasyTeamProfile.categoryTotals(resolve(opp.playerSlugs)),
            meta: fantasyStore.meta, format: appSettings.fantasyFormat, dynastyOn: appSettings.dynastyOn)
    }

    /// Structural gate: each side must move at least one player.
    private var isStructurallyValid: Bool { !incomingSlugs.isEmpty && !outgoingSlugs.isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mySidePanel
                    otherSidePanel
                    verdictSection
                }
                .padding()
            }
            .navigationTitle("Fantasy Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showMyTeamPicker) {
                FantasyTeamPickerSheet(title: "My Team") { picked in
                    myTeamId = picked
                    outgoingSlugs.removeAll()
                }
                .environmentObject(fantasyTeamStore)
            }
            .sheet(isPresented: $showOpponentPicker) {
                FantasyTeamPickerSheet(title: "Opponent") { picked in
                    opponentTeamId = picked
                    incomingSlugs.removeAll()
                }
                .environmentObject(fantasyTeamStore)
            }
            .sheet(isPresented: $showAddIncoming) {
                AddIncomingSheet(pool: incomingPool, selected: incomingSlugs) { slug in
                    let canon = FantasyValueStore.canonicalSlug(slug)
                    if !incomingSlugs.contains(canon) { incomingSlugs.append(canon) }
                }
            }
        }
        .onAppear {
            if myTeamId == nil { myTeamId = fantasyTeamStore.myTeamId }
        }
    }

    // MARK: My side

    @ViewBuilder
    private var mySidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Side").font(.headline)
                Spacer()
                Button { showMyTeamPicker = true } label: {
                    Label(myTeam?.name ?? "Pick team", systemImage: "person.crop.circle").font(.caption)
                }
            }
            if myTeam == nil {
                Text("Create a team first to trade from your roster.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if myRosterSlugs.isEmpty {
                Text("This team has no players yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(myRosterSlugs, id: \.self) { slug in sendRow(slug) }
            }
            if !incomingSlugs.isEmpty {
                Divider()
                Text("Incoming").font(.subheadline.bold())
                ForEach(incomingSlugs, id: \.self) { slug in incomingRow(slug) }
            }
            Button { showAddIncoming = true } label: {
                Label("Add incoming", systemImage: "plus.circle")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func sendRow(_ slug: String) -> some View {
        let sending = outgoingSlugs.contains(slug)
        HStack(spacing: 12) {
            HeadshotImage(slug: playerBySlug[slug]?.slug ?? slug, size: 36)
            Text(playerBySlug[slug]?.name ?? slug).font(.subheadline)
            Spacer()
            Button {
                if sending { outgoingSlugs.removeAll { $0 == slug } }
                else { outgoingSlugs.append(slug) }
            } label: {
                Text(sending ? "Sending" : "Send")
                    .font(.caption.bold())
                    .foregroundStyle(sending ? .red : .accentColor)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)   // HIG tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func incomingRow(_ slug: String) -> some View {
        HStack(spacing: 12) {
            HeadshotImage(slug: playerBySlug[slug]?.slug ?? slug, size: 36)
            Text(playerBySlug[slug]?.name ?? slug).font(.subheadline)
            Spacer()
            Button { incomingSlugs.removeAll { $0 == slug } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)   // HIG tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Other side

    @ViewBuilder
    private var otherSidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Other Side").font(.headline)
                Spacer()
                Button { showOpponentPicker = true } label: {
                    Label(opponentTeam?.name ?? "Any player pool", systemImage: "plus").font(.caption)
                }
            }
            if let opp = opponentTeam {
                if opp.playerSlugs.isEmpty {
                    Text("This team has no players.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(opp.playerSlugs, id: \.self) { slug in opponentSendRow(slug) }
                }
            } else {
                Text("Add incoming players from the whole league via Add incoming.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func opponentSendRow(_ slug: String) -> some View {
        let canon = FantasyValueStore.canonicalSlug(slug)
        let receiving = incomingSlugs.contains(canon)
        HStack(spacing: 12) {
            HeadshotImage(slug: playerBySlug[canon]?.slug ?? slug, size: 36)
            Text(playerBySlug[canon]?.name ?? slug).font(.subheadline)
            Spacer()
            Button {
                if receiving { incomingSlugs.removeAll { $0 == canon } }
                else { incomingSlugs.append(canon) }
            } label: {
                Text(receiving ? "Receiving" : "Send to me")
                    .font(.caption.bold())
                    .foregroundStyle(receiving ? .green : .accentColor)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)   // HIG tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Verdicts

    @ViewBuilder
    private var verdictSection: some View {
        switch FantasyEmptyState.decide(phase: fantasyStore.phase, value: nil) {
        case .loading:
            HStack(spacing: 8) { ProgressView(); Text("Loading fantasy values…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        case .collectionEmpty:
            Text("Fantasy values not available yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        default:
            // Don't show an authoritative-looking verdict for a trade that doesn't exist yet:
            // gate the card on a real (both-sides) trade, else prompt to build one.
            if isStructurallyValid {
                verdictCard(title: "My Side", swing: mySwing)
                if let opp = opponentSwing {
                    verdictCard(title: "Opponent (\(opponentTeam?.name ?? ""))", swing: opp)
                }
                proposeBar
            } else {
                emptyVerdictPrompt
            }
        }
    }

    @ViewBuilder
    private var emptyVerdictPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.title2).foregroundStyle(.secondary)
            Text("Add a player to each side to see the trade verdict.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func verdictCard(title: String, swing: FantasyTradeSwing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack {
                Text("Net fantasy value").foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.2f", swing.netValue))
                    .monospacedDigit().bold()
                    .foregroundStyle(swing.netValue >= 0 ? .green : .red)
            }
            if appSettings.fantasyFormat.isPoints, let fp = swing.fpPerGameDelta {
                HStack {
                    Text("Projected fantasy pts/game").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%+.1f", fp))
                        .monospacedDigit().bold()
                        .foregroundStyle(fp >= 0 ? .green : .red)
                }
            } else {
                Divider()
                ForEach(FantasyCategoryOrder.ordered(swing.categoryDelta), id: \.label) { item in
                    CategoryBarRow(label: item.label, z: item.z)
                }
            }
            Divider()
            ForEach(swing.flags, id: \.self) { flag in flagRow(flag) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func flagRow(_ flag: FantasyTradeFlag) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: flag.kind)).foregroundStyle(color(for: flag.kind))
            Text(flag.text).font(.caption)
            Spacer()
        }
    }

    private func icon(for kind: FantasyTradeFlag.Kind) -> String {
        switch kind {
        case .gain:    return "checkmark.circle.fill"
        case .loss:    return "minus.circle.fill"
        case .neutral: return "equal.circle.fill"
        }
    }

    private func color(for kind: FantasyTradeFlag.Kind) -> Color {
        switch kind {
        case .gain:    return .green
        case .loss:    return .red
        case .neutral: return .gray
        }
    }

    /// This is a WHAT-IF sandbox over the free pool — the verdict card above is the live answer and
    /// nothing is sent anywhere (unlike an in-league proposal, which persists). So instead of a fake
    /// "Propose" CTA, set that expectation honestly.
    @ViewBuilder
    private var proposeBar: some View {
        // Only shown once the trade is structurally valid (see verdictSection); the
        // empty state is handled by emptyVerdictPrompt.
        Label("What-if trade — the verdict above updates live. Nothing is sent anywhere.",
              systemImage: "sparkles")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}

/// Search-add incoming players from a pool (opponent roster or the whole league).
/// Holds its own search `@State`; reports each pick via `onPick` (the caller
/// canonicalizes before appending).
private struct AddIncomingSheet: View {
    let pool: [Player]
    let selected: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var selectedCanon: Set<String> { Set(selected.map { FantasyValueStore.canonicalSlug($0) }) }

    private var filtered: [Player] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return pool.sorted { $0.name < $1.name } }
        return pool.filter { $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q) }
                   .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { p in
                let added = selectedCanon.contains(FantasyValueStore.canonicalSlug(p.slug))
                Button { onPick(p.slug) } label: {
                    HStack(spacing: 12) {
                        HeadshotImage(slug: p.slug, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline)
                            Text("\(p.teamId) · \(p.position)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(added ? .green : .accentColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(added)
            }
            .searchable(text: $query, prompt: "Search players")
            .navigationTitle("Add Incoming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
