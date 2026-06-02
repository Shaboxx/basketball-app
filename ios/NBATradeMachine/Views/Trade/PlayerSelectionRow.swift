import SwiftUI

struct PlayerSelectionRow: View {
    let player: Player
    let seasonOffset: Int
    /// When non-nil, the row replaces salary with an "Expired" chip and
    /// surfaces the re-sign salary instead. The "Expired" label is still
    /// shown when a re-sign exists, but the salary line reflects the new
    /// number so the user sees their pending commitment.
    let displayedSalary: Int
    let isExpired: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    HeadshotImage(slug: player.slug, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.subheadline)
                            if let entry = ownTeamEntry, let tier = entry.tier {
                                TradeTierBadge(tier: tier)
                                EngineChips(tags: player.tradeValue?.tags ?? [])
                            }
                        }
                        Text(player.position).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(salaryText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(isExpired && displayedSalary == 0 ? .orange : .secondary)
                        if let sigma = sigmaLine {
                            Text(sigma)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if isExpired {
                            PlayerChip(
                                label: displayedSalary > 0 ? "Re-signed" : "Expired",
                                background: displayedSalary > 0 ? .green.opacity(0.8) : .expiryChip,
                                foreground: .black
                            )
                        } else if let short = player.contractExpirySeasonShort {
                            PlayerChip(
                                label: "Expires \(short)",
                                background: .expiryChip,
                                foreground: .black
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink(value: player) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var salaryText: String {
        if isExpired && displayedSalary == 0 { return "Re-sign needed" }
        return Money.display(displayedSalary)
    }

    /// Trade Value entry for the player's OWN team — what this roster player
    /// is worth to the team that's about to give them up. Nil when absent.
    private var ownTeamEntry: TradeValue.TeamEntry? {
        let tv = player.tradeValue
        return tv.flatMap { $0.byTeam?[$0.ownTeam ?? ""] }
    }

    /// Compact `OFF +x.xx · DEF +x.xx` line shown under salary; nil for
    /// players without Rev-2 z fields so the row degrades cleanly.
    private var sigmaLine: String? {
        guard let lv = player.latentValue,
              (lv.thetaZOff != nil || lv.thetaZDef != nil)
        else { return nil }
        let o = lv.thetaZOff.map { String(format: "%+.2f", $0) } ?? "—"
        let d = lv.thetaZDef.map { String(format: "%+.2f", $0) } ?? "—"
        return "OFF \(o) · DEF \(d)"
    }
}
