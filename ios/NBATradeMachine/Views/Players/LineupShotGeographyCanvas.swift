import SwiftUI

/// Display modes for the composited lineup shot-geography court.
enum LineupGeographyMode: String, CaseIterable, Identifiable {
    case players, overlap, both
    var id: String { rawValue }
    var label: String { self == .players ? "Players" : (self == .overlap ? "Overlap" : "Both") }
}

/// PURE `nonisolated` view helpers + palette + constants for the lineup shot-geography section.
/// Kept separate from the SwiftUI view so every decision is unit-testable off the render path.
nonisolated enum LineupShotGeography {
    // draw alphas / geometry
    static let DOT_ALPHA_USABLE = 0.55
    static let DOT_ALPHA_THIN = 0.20
    static let DOT_RADIUS_PT: CGFloat = 2.0
    static let OVERLAP_FILL_ALPHA = 0.22
    static let OVERLAP_HATCH_ALPHA = 0.45
    /// Caption when the SAMPLE GATE FAILS (too few usable members / too little FGA) — no reads possible.
    static let gateCaption = "Not enough sample for lineup reads yet."
    /// Caption when the sample gate PASSES but ZERO rules fire — the group is fine, just unremarkable.
    static let noReadsCaption = "No standout spatial reads for this group yet."

    /// The honest caption for the "Spatial read" block: the gate-failed message when the sample gate
    /// fails, the gate-passed/zero-fired message when it passes but no rule fires, else nil (show rows).
    static func spatialReadCaption(gatePassed: Bool, insightCount: Int) -> String? {
        if !gatePassed { return gateCaption }
        if insightCount == 0 { return noReadsCaption }
        return nil
    }

    // Okabe–Ito CVD-safe palette by slot index 0..4.
    static let PALETTE = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#F0E442"]
    static func slotColorHex(_ slot: Int) -> String { PALETTE[max(0, min(4, slot))] }
    static func slotNeedsOutline(_ slot: Int) -> Bool { slot == 4 }   // yellow needs a dark outline

    static func drawsDots(mode: LineupGeographyMode) -> Bool { mode == .players || mode == .both }
    static func drawsOverlap(mode: LineupGeographyMode) -> Bool { mode == .overlap || mode == .both }

    /// Which usable slot indices draw as dots given the isolation set: empty isolation = all usable;
    /// otherwise only the isolated slots (intersected with usable). Order preserved.
    static func visibleDotSlots(usableSlots: [Int], isolated: Set<Int>) -> [Int] {
        isolated.isEmpty ? usableSlots : usableSlots.filter { isolated.contains($0) }
    }

    static func shouldShowSection(matchupsEnabled: Bool) -> Bool { matchupsEnabled }
    static func shouldTriggerLoad(phase: FantasyPhase) -> Bool { phase == .idle }

    static func legendRowIsInteractive(state: SpatialLineupMetrics.MemberState) -> Bool { state == .usable }
    static func legendTag(state: SpatialLineupMetrics.MemberState) -> String? {
        switch state { case .usable: return nil; case .thin: return "thin sample"; case .missing: return "no shot data" }
    }
    static func dotAlpha(state: SpatialLineupMetrics.MemberState) -> Double {
        switch state { case .usable: return DOT_ALPHA_USABLE; case .thin: return DOT_ALPHA_THIN; case .missing: return 0.0 }
    }

    /// Parse a "#RRGGBB" hex into a SwiftUI Color (opaque).
    static func color(hex: String) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
    static func slotColor(_ slot: Int) -> Color { color(hex: slotColorHex(slot)) }
}

/// The composited five-player shot-geography court: court lines -> usable/thin dot layers ->
/// overlap hatch layer, per the display mode + isolation set. PURE inputs (no store); the
/// section builds these once (off the render path) and passes them in.
struct LineupShotGeographyCanvas: View {
    nonisolated struct DotLayer: Identifiable {
        let slot: Int
        let state: SpatialLineupMetrics.MemberState
        let points: [PlayerShotChart.ShotPoint]
        var id: Int { slot }
    }
    let dotLayers: [DotLayer]          // usable + thin members (missing draw nothing)
    let overlapCells: [Int]            // cell indices (row*26+col) that are overlap cells
    let mode: LineupGeographyMode
    let isolated: Set<Int>             // isolated usable slot indices (empty = show all)

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            // 1. court lines (shared helper).
            CourtLines.draw(&ctx, rect)
            // 2. dot layers (usable then thin), subject to mode + isolation.
            if LineupShotGeography.drawsDots(mode: mode) {
                let usableSlots = dotLayers.filter { $0.state == .usable }.map { $0.slot }
                let visible = Set(LineupShotGeography.visibleDotSlots(usableSlots: usableSlots, isolated: isolated))
                // draw usable (visible) first, then thin (always dimmed, never isolated away).
                for layer in dotLayers.sorted(by: { ($0.state == .thin ? 1 : 0) < ($1.state == .thin ? 1 : 0) }) {
                    if layer.state == .usable && !visible.contains(layer.slot) { continue }
                    if layer.state == .missing { continue }
                    drawDots(&ctx, rect, layer)
                }
            }
            // 3. overlap layer ON TOP (never hidden by a dense hue).
            if LineupShotGeography.drawsOverlap(mode: mode) {
                drawOverlap(&ctx, rect)
            }
        }
        .aspectRatio(50.0 / 47.0, contentMode: .fit)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func drawDots(_ ctx: inout GraphicsContext, _ rect: CGRect, _ layer: DotLayer) {
        let alpha = LineupShotGeography.dotAlpha(state: layer.state)
        guard alpha > 0 else { return }
        let base = LineupShotGeography.slotColor(layer.slot).opacity(alpha)
        let r = LineupShotGeography.DOT_RADIUS_PT
        let outline = LineupShotGeography.slotNeedsOutline(layer.slot)
        for p in layer.points {
            let pt = CourtGeometry.point(x: p.x, y: p.y, in: rect)
            let dot = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(base))
            if outline { ctx.stroke(dot, with: .color(Color.primary.opacity(0.5)), lineWidth: 0.5) }
        }
    }

    private func drawOverlap(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        let spacingCG = CGFloat(HeatField.spacing)
        let halfW = rect.width * (spacingCG / (CourtGeometry.xMax - CourtGeometry.xMin)) / 2
        let halfH = rect.height * (spacingCG / (CourtGeometry.yMax - CourtGeometry.yMin)) / 2
        let fill = Color.primary.opacity(LineupShotGeography.OVERLAP_FILL_ALPHA)
        let hatch = Color.primary.opacity(LineupShotGeography.OVERLAP_HATCH_ALPHA)
        for cell in overlapCells {
            let col = cell % 26, row = cell / 26
            let cx = Int((HeatField.xMin + Double(col) * HeatField.spacing).rounded())
            let cy = Int((HeatField.yMin + Double(row) * HeatField.spacing).rounded())
            let c = CourtGeometry.point(x: cx, y: cy, in: rect)
            let cellRect = CGRect(x: c.x - halfW, y: c.y - halfH, width: halfW * 2, height: halfH * 2)
            ctx.fill(Path(cellRect), with: .color(fill))
            // fine diagonal hatch (two lines corner-to-corner region).
            var h = Path()
            h.move(to: CGPoint(x: cellRect.minX, y: cellRect.maxY)); h.addLine(to: CGPoint(x: cellRect.maxX, y: cellRect.minY))
            h.move(to: CGPoint(x: cellRect.minX, y: cellRect.midY)); h.addLine(to: CGPoint(x: cellRect.midX, y: cellRect.minY))
            ctx.stroke(h, with: .color(hatch), lineWidth: 0.5)
        }
    }
}

/// A memoized build result for one lineup: the resolved dot layers, overlap cells, and the
/// engine's insights (or [] when the section gate fails, which drives the honest caption).
nonisolated struct LineupSpatialResult: Equatable {
    let key: String
    let dotLayers: [LineupShotGeographyCanvas.DotLayer]
    let overlapCells: [Int]
    let insights: [SpatialLineupInsight]
    let memberStates: [(name: String, slot: Int, state: SpatialLineupMetrics.MemberState)]
    let gatePassed: Bool

    static func == (l: LineupSpatialResult, r: LineupSpatialResult) -> Bool { l.key == r.key }
}

extension LineupShotGeography {
    /// PURE builder: resolve member states, build ≤5 massGrids + metrics, run the engine. Off the
    /// render path (called from a `.task`, cached by memoKey). `charts[i]` aligns to `members[i]`.
    static func build(members: [SpatialLineupMetrics.MemberInput]) -> LineupSpatialResult {
        let key = SpatialLineupMetrics.memoKey(members: members)
        let states = members.enumerated().map { (i, m) in
            (name: m.name, slot: i, state: SpatialLineupMetrics.state(for: m.chart))
        }
        let usable = members.enumerated().filter { SpatialLineupMetrics.state(for: $0.element.chart) == .usable }
        let usableCharts = usable.compactMap { $0.element.chart }
        let usableGrids = usableCharts.map { HeatField.massGrid(points: $0.points) }
        let overlapCounts = usableGrids.isEmpty ? [] : SpatialLineupMetrics.overlapCounts(grids: usableGrids)
        let overlapCells = overlapCounts.enumerated().filter { $0.element >= 2 }.map { $0.offset }

        // dot layers: usable + thin (missing contribute nothing but are still named in states).
        let dotLayers: [LineupShotGeographyCanvas.DotLayer] = members.enumerated().compactMap { (i, m) in
            let st = SpatialLineupMetrics.state(for: m.chart)
            guard st != .missing, let chart = m.chart else { return nil }
            return LineupShotGeographyCanvas.DotLayer(slot: i, state: st, points: chart.points)
        }

        // build the engine context.
        let combinedUsableFga = usableCharts.reduce(0) { $0 + $1.meta.fga }
        let minUsableFga = usableCharts.map { $0.meta.fga }.min() ?? 0
        let usableProfiles = usableCharts.map { $0.profile }
        let usableNames = usable.map { $0.element.name }
        let excluded = members.enumerated()
            .filter { SpatialLineupMetrics.state(for: $0.element.chart) != .usable }
            .map { $0.element.name }
        let insights = engineInsights(members: members, usable: usable, usableCharts: usableCharts,
                                      usableGrids: usableGrids, usableProfiles: usableProfiles,
                                      usableNames: usableNames, excluded: excluded,
                                      combinedUsableFga: combinedUsableFga, minUsableFga: minUsableFga)
        let gatePassed = usableCharts.count >= SpatialLineupMetrics.MIN_USABLE_MEMBERS
            && combinedUsableFga >= SpatialLineupMetrics.MIN_COMBINED_USABLE_FGA
        return LineupSpatialResult(key: key, dotLayers: dotLayers, overlapCells: overlapCells,
                                   insights: insights, memberStates: states, gatePassed: gatePassed)
    }

    private static func engineInsights(
        members: [SpatialLineupMetrics.MemberInput],
        usable: [(offset: Int, element: SpatialLineupMetrics.MemberInput)],
        usableCharts: [PlayerShotChart], usableGrids: [[Double]],
        usableProfiles: [PlayerShotChart.Profile?], usableNames: [String], excluded: [String],
        combinedUsableFga: Int, minUsableFga: Int) -> [SpatialLineupInsight] {

        let usablePoints = usableCharts.map { $0.points }
        let overlapIndex = SpatialLineupMetrics.overlapIndex(grids: usableGrids)
        let paintOverlap = SpatialLineupMetrics.paintOverlap(grids: usableGrids)
        let contributorCount = SpatialLineupMetrics.overlapContributorCount(grids: usableGrids)
        let dispersion = SpatialLineupMetrics.centroidDispersion(membersPoints: usablePoints)
        let lineup3 = SpatialLineupMetrics.lineupWeightedShare(
            members: usableCharts.map { (fga: $0.meta.fga, profile: $0.profile) }, signalKey: "threeShare")
        let lineupMid = SpatialLineupMetrics.lineupWeightedShare(
            members: usableCharts.map { (fga: $0.meta.fga, profile: $0.profile) }, signalKey: "midShare")
        let perimCount = SpatialLineupMetrics.perimeterShooterCount(profiles: usableProfiles)
        let everyPerim = SpatialLineupMetrics.everyUsableHasPerimeterSignals(profiles: usableProfiles)
        let minThreeSharePct = usableProfiles.compactMap { $0?.signals["threeShare"]?.pct }.count == usableCharts.count
            ? usableProfiles.compactMap { $0?.signals["threeShare"]?.pct }.min() : nil

        // rim-heavy members.
        var rimHeavy: [(name: String, pct: Double)] = []
        for u in usable {
            if let rim = u.element.chart?.profile?.signals["rimShare"],
               rim.pct >= SpatialLineupMetrics.RIM_HEAVY_PCT, rim.value >= SpatialLineupMetrics.RIM_HEAVY_VALUE_MIN {
                rimHeavy.append((u.element.name, rim.pct))
            }
        }
        let rimHeavyMaxPct = rimHeavy.map { $0.pct }.max()

        // lone perimeter (when exactly one).
        var loneName: String? = nil, loneShare: Double? = nil
        if perimCount == 1 {
            if let idx = usable.firstIndex(where: {
                guard let three = $0.element.chart?.profile?.signals["threeShare"],
                      let fg = $0.element.chart?.profile?.signals["threeFgPct"] else { return false }
                return three.pct >= SpatialLineupMetrics.PERIM_3SHARE_PCT && fg.value >= SpatialLineupMetrics.PERIM_3FG_MIN
            }) {
                loneName = usable[idx].element.name
                loneShare = SpatialLineupMetrics.loneVolShare(lonePoints: usable[idx].element.chart!.points,
                                                              allUsablePoints: usablePoints)
            }
        }

        // corners.
        let cornerMembers = usable.map { $0.element }
        let corner = SpatialLineupMetrics.cornerCoverage(members: cornerMembers)
        func claimantShare(_ slug: String?, _ zoneKey: String) -> Double? {
            guard let slug, let m = cornerMembers.first(where: { $0.slug == slug }), let c = m.chart else { return nil }
            let tallied = SpatialLineupMetrics.ALL_ZONES.reduce(0) { $0 + (c.zones[$1]?.fga ?? 0) }
            guard tallied > 0, let z = c.zones[zoneKey] else { return nil }
            return Double(z.fga) / Double(tallied)
        }

        // side skew.
        let (skew, sideAttempts) = SpatialLineupMetrics.sideSkew(membersPoints: usablePoints)
        // dominant side = the larger of M_L / M_R (recompute the counts once for the direction).
        var ml = 0, mr = 0
        for pts in usablePoints {
            for p in pts where SpatialLineupMetrics.inBounds(p) && p.value == 3
                && abs(Double(p.x)) >= SpatialLineupMetrics.SIDE_CENTER_BAND {
                if p.x < 0 { ml += 1 } else if p.x > 0 { mr += 1 }
            }
        }
        let dominantLeft = ml >= mr

        // member percentiles for cited bullets.
        var percentiles: [String: (bucket: String, threeSharePct: Double, rimSharePct: Double)] = [:]
        for u in usable {
            guard let prof = u.element.chart?.profile else { continue }
            let bucket = bucketLabel(prof)
            percentiles[u.element.name] = (bucket: bucket,
                                           threeSharePct: prof.signals["threeShare"]?.pct ?? 0,
                                           rimSharePct: prof.signals["rimShare"]?.pct ?? 0)
        }

        let ctx = SpatialLineupContext(
            usableCount: usableCharts.count, combinedUsableFga: combinedUsableFga, minUsableFga: minUsableFga,
            memberNames: usableNames, excludedNames: excluded,
            perimeterShooterCount: perimCount, everyUsableHasPerimeterSignals: everyPerim,
            minThreeSharePct: minThreeSharePct, loneVolShare: loneShare,
            overlapIndex: overlapIndex, paintOverlap: paintOverlap, overlapContributorCount: contributorCount,
            centroidDispersion: dispersion, lineup3Share: lineup3, lineupMidShare: lineupMid,
            rimHeavyCount: rimHeavy.count, rimHeavyMaxPct: rimHeavyMaxPct, rimHeavyNames: rimHeavy.map { ($0.name, $0.pct) },
            cornerCoverage: corner, leftClaimantShare: claimantShare(corner.leftClaimant, SpatialLineupMetrics.LEFT_CORNER),
            rightClaimantShare: claimantShare(corner.rightClaimant, SpatialLineupMetrics.RIGHT_CORNER),
            sideSkew: skew, sideAttempts: sideAttempts, dominantSideIsLeft: dominantLeft,
            lonePerimeterName: loneName, memberPercentiles: percentiles)
        return SpatialLineupEngine.make(from: ctx)
    }

    /// A citable bucket label (plural) from A's profile bucket — reused for member percentile bullets.
    static func bucketLabel(_ p: PlayerShotChart.Profile) -> String {
        switch p.bucket {
        case "PG": return "point guards"; case "SG": return "shooting guards"; case "SF": return "small forwards"
        case "PF": return "power forwards"; case "C": return "centers"
        case "G": return "guards"; case "F": return "forwards"
        default: return "their position"
        }
    }
}

extension LineupBreakdownView {
    /// The gated "Shot geography" section: segmented control + composited court + legend + the
    /// "Spatial read" block. Owns transient @State via a nested StateObject-free helper view so
    /// LineupBreakdownView itself stays unchanged apart from the one call site.
    @ViewBuilder var shotGeographySection: some View {
        DisclosureGroup {
            ShotGeographyBody(players: players).padding(.top, 6)
        } label: {
            Text("Shot geography").font(.headline)
        }
        .tint(.primary)
    }
}

/// The section body — owns the store phase observation, the display mode, the isolation set, and
/// the memoized build. Consumes PlayerShotStore.shared directly (survives the sheet boundary).
private struct ShotGeographyBody: View {
    let players: [Player]
    @ObservedObject private var store = PlayerShotStore.shared
    @State private var mode: LineupGeographyMode = .players
    @State private var isolated: Set<Int> = []
    @State private var cache: LineupSpatialResult?

    private var members: [SpatialLineupMetrics.MemberInput] {
        players.map { SpatialLineupMetrics.MemberInput(name: $0.name, slug: $0.slug,
                                                       chart: store.chart(for: $0.slug)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.phase == .loading {
                Text("Loading shot charts…").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Display", selection: $mode) {
                ForEach(LineupGeographyMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if let result = cache {
                LineupShotGeographyCanvas(dotLayers: result.dotLayers, overlapCells: result.overlapCells,
                                          mode: mode, isolated: isolated)
                    .frame(height: 300)
                legend(result)
                spatialRead(result)
            }
        }
        .task(id: SpatialLineupMetrics.memoKey(members: members)) {
            if LineupShotGeography.shouldTriggerLoad(phase: store.phase) { await store.load() }
            let built = LineupShotGeography.build(members: members)
            if cache?.key != built.key { cache = built }
        }
    }

    @ViewBuilder private func legend(_ result: LineupSpatialResult) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(result.memberStates, id: \.slot) { ms in
                let interactive = LineupShotGeography.legendRowIsInteractive(state: ms.state)
                Button {
                    guard interactive else { return }
                    if isolated.contains(ms.slot) { isolated.remove(ms.slot) } else { isolated.insert(ms.slot) }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(LineupShotGeography.slotColor(ms.slot))
                            .frame(width: 10, height: 10)
                            .overlay(LineupShotGeography.slotNeedsOutline(ms.slot)
                                     ? Circle().stroke(Color.primary.opacity(0.5), lineWidth: 0.5) : nil)
                        Text(ms.name).font(.caption2)
                        if let tag = LineupShotGeography.legendTag(state: ms.state) {
                            Text(tag).font(.caption2).foregroundStyle(.secondary)
                        }
                        if interactive && isolated.contains(ms.slot) {
                            Image(systemName: "eye").font(.system(size: 9))
                        }
                    }
                    .opacity(ms.state == .missing ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
            }
        }
    }

    @ViewBuilder private func spatialRead(_ result: LineupSpatialResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spatial read").font(.subheadline.weight(.semibold))
            if let caption = LineupShotGeography.spatialReadCaption(gatePassed: result.gatePassed,
                                                                    insightCount: result.insights.count) {
                // gate-failed => "Not enough sample…"; gate-passed but zero rules fire => "No standout…".
                Text(caption).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(result.insights) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(insight.headline).font(.subheadline.weight(.semibold))
                            Text(insight.confidence.rawValue)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((insight.confidence == .high ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                                .foregroundStyle(insight.confidence == .high ? Color.green : Color.orange)
                        }
                        ForEach(insight.evidence, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        Text(insight.basis).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
