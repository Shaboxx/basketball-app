import SwiftUI

// MARK: - Roles

struct RolesSection: View {
    let player: Player
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if player.primaryRole == nil
                && player.secondaryRole == nil
                && player.defensiveRole == nil {
                noDataRow
            } else {
                row("Primary Offensive", player.primaryRole)
                row("Secondary Offensive", player.secondaryRole)
                row("Defensive", player.defensiveRole)
            }
        } label: {
            Text("Roles").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func row(_ key: String, _ value: String?) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Salary

struct SalarySection: View {
    let player: Player
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let amounts = [player.salaryY1, player.salaryY2, player.salaryY3, player.salaryY4]
            if amounts.allSatisfy({ $0 == nil }) {
                noDataRow
            } else {
                ForEach(0..<4, id: \.self) { idx in
                    if let amount = amounts[idx] {
                        salaryRow(label: label(forOffset: idx), amount: amount)
                    }
                }
            }
        } label: {
            Text("Salary").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func label(forOffset offset: Int) -> String {
        if let season = player.seasonLabel(forOffset: offset) { return season }
        return "Year \(offset + 1)"
    }

    private func salaryRow(label: String, amount: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(Money.display(amount)).monospacedDigit().bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

// MARK: - Projected Contract

struct ProjectedContractSection: View {
    let player: Player
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if allFieldsNil {
                noDataRow
            } else {
                if let starts = player.projectedContractStartSeason {
                    row("Starts", starts)
                }
                if let tier = player.maxTierPct {
                    row("Max Tier", "\(tier)%")
                }
                if let nextMax = player.nextContractMax {
                    row("Next Max", Money.display(nextMax))
                }
                if let basis = player.nextContractMaxBasis {
                    row("Basis", basis)
                }
                if let met = player.higherMaxCriteriaMet {
                    row("Higher Max Met", met ? "Yes" : "No")
                }
                if let path = player.supermaxPath {
                    row("Supermax Path", path)
                }
                if let stdMax = player.standardMax {
                    row("Standard Max", Money.display(stdMax))
                }
                if let minSal = player.minSalary {
                    row("Min Salary", Money.display(minSal))
                }
                footer
            }
        } label: {
            Text("Projected Contract").font(.headline)
        }
        .padding()
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var allFieldsNil: Bool {
        player.projectedContractStartSeason == nil
            && player.maxTierPct == nil
            && player.nextContractMax == nil
            && player.nextContractMaxBasis == nil
            && player.higherMaxCriteriaMet == nil
            && player.supermaxPath == nil
            && player.standardMax == nil
            && player.minSalary == nil
    }

    @ViewBuilder private var footer: some View {
        if player.cbaSeason != nil || player.cbaUpdatedRelative != nil {
            HStack {
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if let season = player.cbaSeason { parts.append("CBA \(season)") }
        if let rel = player.cbaUpdatedRelative { parts.append("updated \(rel)") }
        return parts.joined(separator: " · ")
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .padding(.top, 6)
    }

    private var noDataRow: some View {
        Text("— No data")
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}
