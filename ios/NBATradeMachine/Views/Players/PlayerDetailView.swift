import SwiftUI

struct PlayerDetailView: View {
    /// The player being shown. Mutable so next/prev can swap it in place without
    /// a back-out-and-re-descend round-trip (NAV-04).
    @State private var player: Player
    /// The sibling list to page through (e.g. the filtered Players list). Empty
    /// by default so every existing push site compiles and simply shows no
    /// pager — only surfaces I can pass a real ordering opt in.
    private let siblings: [Player]

    @EnvironmentObject private var normsVM: LeagueNormsViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var fantasyStore: FantasyValueStore

    init(player: Player, siblings: [Player] = []) {
        _player = State(initialValue: player)
        self.siblings = siblings
    }

    /// Index of the current player within `siblings`, when it's a pageable list.
    private var siblingIndex: Int? {
        guard siblings.count > 1 else { return nil }
        return siblings.firstIndex(of: player)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeadshotImage(slug: player.slug, size: 160)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(player.name).font(.title.bold())
                    Text("\(player.teamId) · \(player.position)")
                        .foregroundStyle(.secondary)
                    chipRow
                }

                HStack(spacing: 20) {
                    stat("Height", player.heightDisplay)
                    stat("Weight", player.weightLbs.map { "\($0) lb" } ?? "—")
                    stat("Age", player.age().map { String($0) } ?? "—")
                }
                if AppConfig.fantasyEnabled && appSettings.fantasyModeOn {
                    HStack(spacing: 20) {
                        // Fantasy mode: format values replace the NBA TOT/OFF/DEF trio.
                        let fv = fantasyStore.value(for: player.slug)
                        stat("9-Cat", fv.map { fmtFantasy($0.formats.nineCat.value) } ?? "—")
                        stat("8-Cat", fv.map { fmtFantasy($0.formats.eightCat.value) } ?? "—")
                        stat("Points", fv.map {
                            fmtFantasy(FantasyHeaderPoints.entry($0, format: appSettings.fantasyFormat).value)
                        } ?? "—")
                    }
                } else {
                    Text("SwishScore")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        stat("OVR", Player.fmtVal(player.dispTotal))
                        stat("OFF", Player.fmtVal(player.dispOff))
                        stat("DEF", Player.fmtVal(player.dispDef))
                    }
                }
                if !(AppConfig.fantasyEnabled && appSettings.fantasyModeOn) {
                    Text("SwishScore — holistic on-court impact rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                PlayerStatsSection(player: player)

                RolesSection(player: player)
                NewsSection(player: player)
                if AppConfig.fantasyEnabled && appSettings.fantasyModeOn {
                    FantasyValueSection(player: player)
                    if AppConfig.fantasySeasonalEnabled {
                        FantasySeasonalValueSection(player: player)
                    }
                    CategoryBreakdownSection(player: player)
                    FantasyBoxSection(player: player)
                } else {
                    LatentValueSection(player: player)
                    SalarySection(player: player)
                    ProjectedContractSection(player: player)
                    if AppConfig.matchupsEnabled {
                        MatchupCourtSection(player: player)
                    }
                }

                AdBanner()   // bottom-of-page banner slot; self-hides when ads are off
            }
            .padding()
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        // Register here (not just in the News tab) so the value-routed NewsRow
        // links inside NewsSection resolve in EVERY stack that shows a player
        // profile — fixes the silent-fail news tap (NAV-06).
        .navigationDestination(for: NewsItem.self) { NewsDetailView(item: $0) }
        // Game-log drill-down: tapping a season row in PlayerStatsSection pushes this.
        .navigationDestination(for: PlayerGameLogRoute.self) {
            PlayerGameLogView(slug: $0.slug, initialSeason: $0.season)
        }
        .toolbar {
            // Page to the adjacent player in the list without backing out
            // (NAV-04). Only shown when a real sibling ordering was passed in.
            if let idx = siblingIndex {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if idx > 0 { player = siblings[idx - 1] }
                    } label: { Image(systemName: "chevron.up") }
                        .disabled(idx == 0)
                        .accessibilityLabel("Previous player")
                    Button {
                        if idx < siblings.count - 1 { player = siblings[idx + 1] }
                    } label: { Image(systemName: "chevron.down") }
                        .disabled(idx == siblings.count - 1)
                        .accessibilityLabel("Next player")
                }
            }
        }
    }

    @ViewBuilder
    private var chipRow: some View {
        let tags = player.playerTags
        let expiry = player.contractExpirySeason
        VStack(spacing: 6) {
            if !tags.isEmpty || expiry != nil {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        PlayerChip(
                            label: tag.label,
                            background: tag.background,
                            foreground: tag.foreground
                        )
                    }
                    if let expiry {
                        PlayerChip(
                            label: "Expires \(expiry)",
                            background: .expiryChip,
                            foreground: .black
                        )
                    }
                }
            }
            profileLabelRow
        }
        .padding(.top, 4)
    }

    /// Dynamic best-3 descriptive profile labels, rendered beneath the existing
    /// status / "Expires" chip row. Uses a subtle neutral chip style so they
    /// read as descriptive labels rather than status badges.
    @ViewBuilder
    private var profileLabelRow: some View {
        let labels = PlayerProfileLabels.labels(for: player, norms: normsVM.norms)
        if !labels.isEmpty {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    PlayerChip(
                        label: label.text,
                        background: Color(.tertiarySystemFill),
                        foreground: .primary
                    )
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fmtFantasy(_ v: Double) -> String { String(format: "%.1f", v) }
}

