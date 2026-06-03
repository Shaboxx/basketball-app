import SwiftUI

/// Re-sign UI for an expired roster player. Shown in offseason mode when
/// the user taps an "Expired" row. Salary is hard-clamped to the CBA
/// min/max band; values inside the band but outside the realistic window
/// raise a soft warning the user can override with "Keep my offer" or
/// retry with "Redo contract".
struct ResignContractSheet: View {
    let player: Player
    let teamId: String
    @ObservedObject var vm: TradeMachineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var salaryText: String = ""
    @State private var years: Int = 2
    @State private var showSoftWarning = false
    @State private var pendingCommit: (salary: Int, years: Int)?

    private static let fallbackVetMin = 2_000_000
    private static let fallbackMax = 75_000_000

    /// Phase-7 value-model suggestion: the cost-cone point — what the model
    /// thinks this player should be *paid* next, given their production.
    /// Preferred over `nextContractMax` (which is only the player's *maximum
    /// eligible* contract) so the default reflects value, not max.
    private var modelPoint: Int? { player.compZ?.cost?.pointDollars }

    /// Default ask: existing override → model cost-cone point → CBA next-max
    /// → current salary. Capped at min/max so the initial field is always a
    /// legal value.
    private var defaultSalary: Int {
        if let prior = vm.resignedContract(for: player.id) { return prior.salary }
        let anchor = modelPoint
            ?? player.nextContractMax
            ?? (player.currentSalary > 0 ? player.currentSalary : hardMin)
        return min(hardMax, max(hardMin, anchor))
    }

    private var defaultYears: Int {
        vm.resignedContract(for: player.id)?.years ?? 2
    }

    private var hardMin: Int { player.minSalary ?? Self.fallbackVetMin }
    private var hardMax: Int { player.standardMax ?? Self.fallbackMax }

    /// Anchor for the realistic band: the value-model cost-cone point when
    /// available, else the CBA max / current-salary fallback. Anchoring on
    /// the model (not the max) is what stops every veteran's "realistic
    /// floor" from being 60% of a *maximum* contract.
    private var anchorBase: Int {
        modelPoint ?? player.nextContractMax ?? player.currentSalary
    }

    /// "Realistic" band: 0.6×–1.05× of the anchor. The lower bound mirrors
    /// veterans who took heavy haircuts; the upper bound is intentionally
    /// tight so the warning fires whenever a team offers a premium over the
    /// model's read that wouldn't pass a real front office.
    private var softLow: Int {
        max(hardMin, Int(Double(anchorBase) * 0.6))
    }
    private var softHigh: Int {
        min(hardMax, Int(Double(anchorBase) * 1.05))
    }

    private var parsedSalary: Int {
        Int(salaryText.filter(\.isNumber)) ?? 0
    }

    private var hardError: String? {
        let s = parsedSalary
        if s < hardMin {
            return "Below league minimum (\(Money.display(hardMin)))."
        }
        if s > hardMax {
            return "Above player maximum (\(Money.display(hardMax)))."
        }
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
                        HeadshotImage(slug: player.slug, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).font(.headline)
                            Text("\(player.position) · contract expired").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Salary") {
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
                    bandLegend
                }

                if let err = hardError {
                    Section {
                        Label(err, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let cz = player.compZ {
                    Section("Model valuation") {
                        if let point = cz.cost?.pointDollars {
                            detailRow("Suggested (model)", Money.display(point))
                        }
                        if let lo = cz.cost?.floorDollars,
                           let hi = cz.cost?.ceilingDollars {
                            detailRow("Model range",
                                      "\(Money.display(lo)) – \(Money.display(hi))")
                        }
                        if let conclusion = player.contractConclusion {
                            detailRow("Conclusion", conclusion)
                        }
                    }
                }

                Section("Anchor") {
                    detailRow("Current salary", Money.display(player.currentSalary))
                    if let next = player.nextContractMax {
                        detailRow("CBA next max", Money.display(next))
                    }
                    if let basis = player.nextContractMaxBasis {
                        detailRow("Max basis", basis)
                    }
                    if player.supermaxEligible == true {
                        detailRow("Supermax eligible", "yes")
                    }
                }
            }
            .navigationTitle("Re-sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTapped() }
                        .disabled(hardError != nil || parsedSalary <= 0)
                }
            }
            .alert("Unusual offer", isPresented: $showSoftWarning) {
                Button("Keep my offer") { commit() }
                Button("Redo contract", role: .cancel) {
                    pendingCommit = nil
                }
            } message: {
                Text(softWarning ?? "")
            }
        }
        .onAppear {
            salaryText = String(defaultSalary)
            years = defaultYears
        }
    }

    private func saveTapped() {
        guard hardError == nil, parsedSalary > 0 else { return }
        if softWarning != nil {
            pendingCommit = (parsedSalary, years)
            showSoftWarning = true
            return
        }
        commit()
    }

    private func commit() {
        let salary = pendingCommit?.salary ?? parsedSalary
        let yrs = pendingCommit?.years ?? years
        vm.signResignContract(player: player, salary: salary, years: yrs)
        pendingCommit = nil
        dismiss()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    /// Compact line that surfaces the min/max guardrails plus the realistic
    /// window so the user knows where they stand before typing. Color is
    /// muted on purpose — the hard error and soft alert do the loud work.
    private var bandLegend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Allowed: \(Money.display(hardMin)) – \(Money.display(hardMax))")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Realistic: \(Money.display(softLow)) – \(Money.display(softHigh))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
