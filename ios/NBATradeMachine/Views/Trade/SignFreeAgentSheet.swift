import SwiftUI

/// "Sign Player" surface in offseason mode. Lists every FA loaded from
/// the bundled `free-agents.json`, labels UFA vs RFA, dedupes ones already
/// signed across the whole trade, and routes the chosen FA into a signing
/// detail with the same min/max + soft-window logic as `ResignContractSheet`.
struct SignFreeAgentSheet: View {
    let teamId: String
    @ObservedObject var vm: TradeMachineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var kindFilter: KindFilter = .all
    @State private var selected: FreeAgent?

    private let allFAs: [FreeAgent] = FreeAgentsService.load()

    enum KindFilter: String, CaseIterable, Identifiable {
        case all, ufa, rfa
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .ufa: return "UFA"
            case .rfa: return "RFA"
            }
        }
    }

    /// Visible FAs after filter/search, minus anyone already signed in
    /// this trade so the user can't pick the same player twice.
    private var visible: [FreeAgent] {
        let taken = vm.allSignedFreeAgentIds()
        let q = query.lowercased()
        return allFAs.filter { fa in
            if taken.contains(fa.id) { return false }
            switch kindFilter {
            case .all: break
            case .ufa: if fa.kind != .unrestricted { return false }
            case .rfa: if fa.kind != .restricted { return false }
            }
            if q.isEmpty { return true }
            return fa.name.lowercased().contains(q)
                || fa.position.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $kindFilter) {
                    ForEach(KindFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8)

                if allFAs.isEmpty {
                    emptyState
                } else if visible.isEmpty {
                    Text("No free agents match your filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    List(visible) { fa in
                        Button { selected = fa } label: {
                            row(fa)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: "Search free agents")
                }
            }
            .navigationTitle("Sign Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selected) { fa in
                SignFreeAgentDetail(fa: fa, teamId: teamId, vm: vm) {
                    selected = nil
                    dismiss()
                }
            }
        }
    }

    private func row(_ fa: FreeAgent) -> some View {
        HStack(spacing: 12) {
            HeadshotImage(slug: fa.slug ?? fa.id, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(fa.name).font(.subheadline)
                    Text(fa.kind.shortLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            (fa.kind == .unrestricted ? Color.green : Color.orange)
                                .opacity(0.18),
                            in: Capsule()
                        )
                }
                Text(detailLine(for: fa))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let exp = fa.expectedSalary {
                Text(Money.display(exp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailLine(for fa: FreeAgent) -> String {
        var parts = [fa.position]
        if let prior = fa.priorTeamId { parts.append("Last: \(prior)") }
        return parts.joined(separator: " · ")
    }

    /// Shown when the bundled JSON is missing or empty. Spells out what the
    /// next step looks like so the user knows the surface is wired up and
    /// the data is the only thing waiting.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("No free agent data loaded.")
                .font(.subheadline)
            Text("Add `free-agents.json` to the app bundle to populate this list.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 60)
    }
}

/// Per-FA signing form. Shares the structure of `ResignContractSheet` but
/// reads its anchor band from the FA record rather than the player's CBA
/// fields. Commits a `SignedFreeAgent` to the VM on save.
struct SignFreeAgentDetail: View {
    let fa: FreeAgent
    let teamId: String
    @ObservedObject var vm: TradeMachineViewModel
    let onSigned: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var salaryText: String = ""
    @State private var years: Int = 2
    @State private var showSoftWarning = false
    @State private var exceptionUsed: ExceptionType = .capSpace
    @State private var isSignAndTrade: Bool = false

    private static let fallbackVetMin = 2_000_000
    private static let fallbackMax = 75_000_000

    private var hardMin: Int { fa.minSalary ?? Self.fallbackVetMin }
    private var hardMax: Int { fa.maxSalary ?? Self.fallbackMax }

    /// The rostered `Player` matching this free agent (by slug/id), when one
    /// is loaded — the carrier of the Phase-7 cost cone. Free agents come from
    /// a separate bundled file with no `compZ` of their own, so we resolve the
    /// matching player through the view model.
    private var matchedPlayer: Player? { vm.player(matchingSlugOrId: fa.slug ?? fa.id) }

    /// Value-model cost-cone point, when the matching player and its cone are
    /// loaded — what the model thinks this FA should be paid.
    private var modelPoint: Int? { matchedPlayer?.compZ?.cost?.pointDollars }

    /// Anchor: model cost-cone point → bundled market estimate → hard min.
    /// Anchoring on the model (when present) ties the suggested offer to
    /// production rather than a hand-entered guess.
    private var anchor: Int { modelPoint ?? fa.expectedSalary ?? hardMin }
    private var softLow: Int { max(hardMin, Int(Double(anchor) * 0.6)) }
    private var softHigh: Int { min(hardMax, Int(Double(anchor) * 1.05)) }

    private var parsedSalary: Int { Int(salaryText.filter(\.isNumber)) ?? 0 }

    private var hardError: String? {
        let s = parsedSalary
        if s < hardMin { return "Below minimum (\(Money.display(hardMin)))." }
        if s > hardMax { return "Above maximum (\(Money.display(hardMax)))." }
        return nil
    }

    private var softWarning: String? {
        guard hardError == nil else { return nil }
        let s = parsedSalary
        if s < softLow {
            return "Unlikely the player signs for so little — expected band starts around \(Money.display(softLow))."
        }
        if s > softHigh {
            return "Unlikely the team offers this much — expected band tops out around \(Money.display(softHigh))."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    HStack(spacing: 12) {
                        HeadshotImage(slug: fa.slug ?? fa.id, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(fa.name).font(.headline)
                                Text(fa.kind.shortLabel)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.18), in: Capsule())
                            }
                            Text(fa.position).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Offer") {
                    HStack {
                        Text("Annual").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("Salary", text: $salaryText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 180)
                    }
                    HStack {
                        Text("Display").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.display(parsedSalary))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Years: \(years)", value: $years, in: 1...4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allowed: \(Money.display(hardMin)) – \(Money.display(hardMax))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Realistic: \(Money.display(softLow)) – \(Money.display(softHigh))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Exception") {
                    Toggle("Sign-and-trade", isOn: $isSignAndTrade)
                    if isSignAndTrade {
                        if let prior = fa.priorTeamId {
                            HStack {
                                Text("Prior team").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(prior).font(.caption.monospacedDigit())
                            }
                            Text("The prior team must be a participant in this trade. The acquirer is hard-capped at the first apron.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("This free agent has no recorded prior team — sign-and-trade can't be modeled.")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    } else {
                        Picker("Used", selection: $exceptionUsed) {
                            ForEach(ExceptionType.allCases.filter { $0 != .signAndTrade }, id: \.self) { ex in
                                Text(ex.label).tag(ex)
                            }
                        }
                        if exceptionUsed.hardCapsAtFirstApron {
                            Text("Using this hard-caps the team at the first apron for the season.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if let cz = matchedPlayer?.compZ {
                    Section("Model valuation") {
                        if let point = cz.cost?.pointDollars {
                            modelRow("Suggested (model)", Money.display(point))
                        }
                        if let lo = cz.cost?.floorDollars,
                           let hi = cz.cost?.ceilingDollars {
                            modelRow("Model range",
                                     "\(Money.display(lo)) – \(Money.display(hi))")
                        }
                        if let verdict = cz.verdict, !verdict.isEmpty {
                            modelRow("Verdict", verdict)
                        }
                    }
                }

                if let err = hardError {
                    Section {
                        Label(err, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign") { signTapped() }
                        .disabled(hardError != nil || parsedSalary <= 0)
                }
            }
            .alert("Unusual offer", isPresented: $showSoftWarning) {
                Button("Keep my offer") { commit() }
                Button("Redo contract", role: .cancel) {}
            } message: {
                Text(softWarning ?? "")
            }
        }
        .onAppear {
            salaryText = String(min(hardMax, max(hardMin, anchor)))
        }
    }

    private func modelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func signTapped() {
        guard hardError == nil, parsedSalary > 0 else { return }
        if softWarning != nil { showSoftWarning = true; return }
        commit()
    }

    private func commit() {
        let signed = TradeMachineViewModel.SignedFreeAgent(
            id: fa.id, name: fa.name, position: fa.position,
            salary: parsedSalary, years: years, kind: fa.kind,
            exceptionUsed: isSignAndTrade ? .signAndTrade : exceptionUsed,
            isSignAndTrade: isSignAndTrade,
            priorTeamId: isSignAndTrade ? fa.priorTeamId : nil
        )
        vm.signFreeAgent(signed, to: teamId)
        dismiss()
        onSigned()
    }
}
