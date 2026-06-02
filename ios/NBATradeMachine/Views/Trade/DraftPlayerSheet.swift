import SwiftUI

/// "Draft Player" surface. Shows the active team's owned picks in the
/// current draft year, lets the user choose which pick to consume, runs a
/// team-before simulation that grays prospects with consensus rank below
/// that pick's slot, then commits the user's choice as a `DraftedProspect`.
///
/// The sim does not actually attribute the pre-claimed picks to specific
/// teams because we don't have the 2026 draft order data; instead the
/// greyed entries are simply labeled "Drafted". When `draft-2026.json`
/// is absent the sheet falls back to an empty state.
struct DraftPlayerSheet: View {
    let team: Team
    @ObservedObject var vm: TradeMachineViewModel
    @EnvironmentObject var picksVM: PicksViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPickId: UUID?
    @State private var pendingProspect: DraftProspect?

    private let allProspects: [DraftProspect] = DraftService.loadProspects()
    private let draftYear = DraftService.defaultYear

    /// Picks the team owns in the active draft year. Excludes picks already
    /// shipped out in the in-progress trade so the user can't draft with
    /// an asset they just dealt.
    private var availablePicks: [Pick] {
        // Picks lose their original UUID when copied into a movement
        // (Pick.init regenerates id), so compare by source+year+round
        // instead of identity.
        let outgoing = Set(
            vm.trade.picksOutgoing(from: team.teamId).map { Self.matchKey($0.pick) }
        )
        return picksVM.picks(for: team.teamId)
            .filter { $0.year == draftYear && !outgoing.contains(Self.matchKey($0)) }
            .sorted { ($0.round, $0.projectedPosition ?? 60) < ($1.round, $1.projectedPosition ?? 60) }
    }

    private static func matchKey(_ p: Pick) -> String {
        "\(p.originatingTeamId)|\(p.year)|\(p.round)"
    }

    private var selectedPick: Pick? {
        guard let id = selectedPickId else { return availablePicks.first }
        return availablePicks.first { $0.id == id } ?? availablePicks.first
    }

    /// Overall slot for the currently selected pick (1-60). Second-round
    /// projected positions get offset by 30 so the sim grays the full
    /// first round before second-rounders.
    private var selectedSlot: Int {
        guard let pick = selectedPick else { return 1 }
        let base = pick.projectedPosition ?? (pick.round == 1 ? 30 : 60)
        return pick.round == 2 ? max(31, base + (base <= 30 ? 30 : 0)) : base
    }

    /// Prospects already drafted somewhere in this trade. The sheet shows
    /// them disabled with the claiming team's id so the user can see who
    /// took them, mirroring the team-before sim's intent for sim picks.
    private var userClaimedById: [String: String] {
        var map: [String: String] = [:]
        for (tid, list) in vm.draftedProspects {
            for p in list { map[p.id] = tid }
        }
        return map
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if availablePicks.isEmpty {
                    emptyPicksState
                } else if allProspects.isEmpty {
                    emptyProspectsState
                } else {
                    pickSelector
                    Divider()
                    prospectList
                }
            }
            .navigationTitle("Draft \(draftYear)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $pendingProspect) { prospect in
                confirmDraftSheet(for: prospect)
            }
            .onAppear {
                if selectedPickId == nil { selectedPickId = availablePicks.first?.id }
            }
        }
    }

    private var pickSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availablePicks) { pick in
                    Button {
                        selectedPickId = pick.id
                    } label: {
                        pickChip(pick, selected: pick.id == (selectedPick?.id ?? UUID()))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func pickChip(_ pick: Pick, selected: Bool) -> some View {
        let slot = pick.projectedPosition.map { "#\($0)" } ?? "R\(pick.round)"
        return VStack(spacing: 2) {
            Text(slot).font(.caption.bold().monospacedDigit())
            Text("\(pick.round == 1 ? "1st" : "2nd")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private var prospectList: some View {
        let slot = selectedSlot
        let claimed = userClaimedById
        return List(allProspects) { prospect in
            let claimedBy = claimed[prospect.id]
            let isSim = prospect.consensusRank < slot && claimedBy == nil
            let unavailable = isSim || claimedBy != nil
            Button {
                guard !unavailable else { return }
                pendingProspect = prospect
            } label: {
                prospectRow(prospect, isSim: isSim, claimedBy: claimedBy, slot: slot)
            }
            .buttonStyle(.plain)
            .disabled(unavailable)
        }
        .listStyle(.plain)
    }

    private func prospectRow(
        _ prospect: DraftProspect, isSim: Bool, claimedBy: String?, slot: Int
    ) -> some View {
        let dimmed = isSim || claimedBy != nil
        return HStack(spacing: 12) {
            HeadshotImage(slug: prospect.slug ?? prospect.id, size: 36)
                .opacity(dimmed ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(prospect.name)
                    .font(.subheadline)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Text(detailLine(for: prospect))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("#\(prospect.consensusRank)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
                if let tid = claimedBy {
                    Text("Claimed by \(tid)")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                } else if isSim {
                    Text("Drafted")
                        .font(.caption2.bold())
                        .foregroundStyle(.red.opacity(0.7))
                } else if prospect.consensusRank == slot {
                    Text("On the clock")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func detailLine(for prospect: DraftProspect) -> String {
        var parts = [prospect.position]
        if let s = prospect.school { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    private func confirmDraftSheet(for prospect: DraftProspect) -> some View {
        let slot = selectedSlot
        let pick = selectedPick
        let rookieSalary = RookieScale.salary(
            forOverallSlot: slot, round: pick?.round ?? 1
        )
        return NavigationStack {
            Form {
                Section("Selecting") {
                    HStack(spacing: 12) {
                        HeadshotImage(slug: prospect.slug ?? prospect.id, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prospect.name).font(.headline)
                            Text(detailLine(for: prospect))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("With pick") {
                    HStack {
                        Text("Slot").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("#\(slot)").font(.caption.monospacedDigit())
                    }
                    HStack {
                        Text("Round").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(pick?.round == 2 ? "2nd" : "1st").font(.caption)
                    }
                    HStack {
                        Text("Rookie scale").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.display(rookieSalary)).font(.caption.monospacedDigit())
                    }
                }
            }
            .navigationTitle("Confirm draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingProspect = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Draft") {
                        commit(prospect, slot: slot, pick: pick, salary: rookieSalary)
                    }
                }
            }
        }
    }

    private func commit(_ prospect: DraftProspect, slot: Int, pick: Pick?, salary: Int) {
        let drafted = TradeMachineViewModel.DraftedProspect(
            id: prospect.id,
            name: prospect.name,
            position: prospect.position,
            pickOverall: slot,
            pickYear: draftYear,
            pickRound: pick?.round ?? 1,
            rookieScaleSalary: salary
        )
        vm.draftProspect(drafted, to: team.teamId)
        pendingProspect = nil
        dismiss()
    }

    private var emptyPicksState: some View {
        VStack(spacing: 8) {
            Image(systemName: "ticket")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("\(team.teamId) owns no \(draftYear) picks.")
                .font(.subheadline)
            Text("Trade for a pick to use the draft.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 60).frame(maxWidth: .infinity)
    }

    private var emptyProspectsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.diamond")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("No \(draftYear) prospect data loaded.")
                .font(.subheadline)
            Text("Add `draft-\(draftYear).json` to the app bundle to populate this list.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60).frame(maxWidth: .infinity)
    }
}
