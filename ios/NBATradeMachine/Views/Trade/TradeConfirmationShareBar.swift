import SwiftUI
import UIKit

/// Bottom share bar for `TradeConfirmationView`.
///
/// Surfaces two share affordances:
///   1. **Image** — a single PNG rendered from a paginated, padded copy of
///      the trade confirmation surface (so the screenshot is self-contained
///      regardless of the on-screen scroll position).
///   2. **Text** — `TradeShareText.render(...)`, the deterministic plain-text
///      summary suitable for iMessage / Mail.
///
/// Two separate ShareLinks are used (rather than a single multi-item share)
/// so the bar works on iOS 16 — iOS 17's `SharePreview` collection initializer
/// is not required.
struct TradeConfirmationShareBar: View {
    let trade: Trade
    let confirmation: TradeConfirmation
    let playersById: [String: Player]

    /// Display scale, read from the environment so we avoid the deprecated
    /// `UIScreen.main` global and stay correct on multi-window / external
    /// display setups.
    @Environment(\.displayScale) private var displayScale

    /// Cached rendered image. We populate this once in `.task` so the
    /// synchronous `ImageRenderer.uiImage` pass doesn't run on every body
    /// re-evaluation (which on complex surfaces can stall the main thread
    /// for long enough to look like a blank screen).
    @State private var cachedImage: Image?

    var body: some View {
        HStack(spacing: 12) {
            ShareLink(
                item: cachedImage ?? Image(systemName: "doc.text"),
                preview: SharePreview(
                    "Trade summary",
                    image: cachedImage ?? Image(systemName: "doc.text")
                )
            ) {
                Label("Share image", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cachedImage == nil)

            ShareLink(item: textPayload) {
                Label("Share text", systemImage: "doc.plaintext")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
        .task(id: snapshotKey) {
            cachedImage = renderImage()
        }
    }

    /// Runs ImageRenderer once per snapshot. MainActor-isolated because the
    /// renderer must be touched on the main actor.
    @MainActor
    private func renderImage() -> Image {
        let exportable = TradeConfirmationExportSurface(confirmation: confirmation)
        let renderer = ImageRenderer(content: exportable)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "doc.text")
    }

    private var textPayload: String {
        TradeShareText.render(trade, playersById: playersById)
    }

    /// Stable identifier for the rendered snapshot — re-renders only when
    /// the team line-up changes (drives `.task(id:)`).
    private var snapshotKey: String {
        confirmation.teams.map(\.id).joined(separator: "|")
    }
}

/// The export-only surface rendered into a PNG. Mirrors the on-screen layout
/// but always vertically stacks (one tall image) and pads its background so
/// the result reads as a single, self-contained "trade card" regardless of
/// the device that produced it. Decoupled from the live view so scroll
/// position and toolbar chrome never bleed into the screenshot.
struct TradeConfirmationExportSurface: View {
    let confirmation: TradeConfirmation
    private let columnWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Trade Summary")
                .font(.title2.weight(.semibold))
            ForEach(confirmation.teams) { pkg in
                ExportTeamCard(package: pkg)
            }
            ExportPhase7fStrip(
                chemistry: confirmation.chemistry,
                peakTimeline: confirmation.peakTimeline
            )
        }
        .padding(20)
        .frame(width: columnWidth + 40)
        .background(Color(.systemBackground))
    }
}

private struct ExportTeamCard: View {
    let package: TradeConfirmation.TeamPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(package.team.fullName.uppercased())
                .font(.caption).foregroundStyle(.secondary)
            Text("receive").font(.headline)
            if package.incomingPlayers.isEmpty
                && package.incomingPicks.isEmpty
                && package.cashOutgoing == 0 {
                Text("Nothing.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(package.incomingPlayers) { p in
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        if let s = p.salaryY1 {
                            Text(_formatDollars(s))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(package.incomingPicks) { pick in
                    Text("Pick: \(pick.shortLabel)")
                        .font(.caption)
                }
                if package.cashOutgoing > 0 {
                    Text("Cash: \(_formatDollars(package.cashOutgoing))")
                        .font(.caption)
                }
            }
            Divider()
            ExportRollupRow(rollup: package.rollup)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct ExportRollupRow: View {
    let rollup: TradeConfirmation.Rollup

    var body: some View {
        HStack(spacing: 16) {
            cell(label: "Asset Δ",
                 value: rollup.assetDeltaDollars.map { _formatSignedDollars($0) } ?? "—")
            cell(label: "OFF Δσ",
                 value: rollup.offDeltaLeagueZ.map { String(format: "%+.2f", $0) } ?? "—")
            cell(label: "DEF Δσ",
                 value: rollup.defDeltaLeagueZ.map { String(format: "%+.2f", $0) } ?? "—")
        }
        .font(.caption.monospacedDigit())
    }

    private func cell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private struct ExportPhase7fStrip: View {
    let chemistry: ChemistryReport?
    let peakTimeline: PeakTimelineForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = chemistry?.summary {
                Text("Chemistry: \(s)").font(.caption2)
            }
            if let p = peakTimeline,
               let a = p.peakStartSeason, let b = p.peakEndSeason {
                Text("Peak: \(a) – \(b)").font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Private formatters (file-private, do not reuse view internals)

private func _formatDollars(_ value: Int) -> String {
    let abs = Swift.abs(value)
    if abs >= 1_000_000 {
        return String(format: "$%.2fM", Double(value) / 1_000_000)
    }
    if abs >= 1_000 {
        return String(format: "$%.0fK", Double(value) / 1_000)
    }
    return "$\(value)"
}

private func _formatSignedDollars(_ value: Int) -> String {
    let sign = value >= 0 ? "+" : "−"
    return "\(sign)\(_formatDollars(Swift.abs(value)))"
}
