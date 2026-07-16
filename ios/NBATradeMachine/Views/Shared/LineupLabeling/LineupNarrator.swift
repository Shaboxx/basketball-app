import Foundation

/// Generates plain-language, player+stat-cited prose for a five-man lineup from
/// data the app ALREADY computes — the `LineupLabel` verdicts plus each player's
/// `LineupFeatures`, ranked against `LeagueNorms`. No backend fetch, no AI: it
/// explains the reasoning behind the tags/capabilities the breakdown already
/// shows, and it works for ANY lineup (every depth layer, every custom five).
///
/// Output reuses the layered `LineupSuggestionReport` shape (`basic` headlines +
/// `detail` per-category items) so the existing Analysis UI renders it unchanged.
///
/// Conservative on negatives: a shooting knock is gated by three-point VOLUME — a
/// player who rarely shoots threes reads "untested from deep" (low confidence),
/// never "can't shoot". Absence-of-positive findings across the whole five (e.g.
/// no rim protector) are observable from all five records, so they are stated
/// plainly.
nonisolated enum LineupNarrator {

    // Percent-scale features (fg3_pct/blk_pct/usg are 0..100); box_creation/pace raw.
    private static let coldPctile = 0.40        // 3P% below this percentile -> a spacing tax
    private static let hotPctile = 0.60         // 3P% at/above -> a live shooter
    private static let lowVolumeThreePar = 20.0  // 3PA share (% of FGA) below this -> "untested", not "can't shoot"
    private static let anchorBlkPctile = 0.65   // rim-anchor cutoff (block rate)
    private static let rimDefPctile = 0.75      // secondary anchor: holds opponents below average at the rim
    private static let highUsagePctile = 0.65   // lead-creator cutoff
    private static let switchPctile = 0.60       // versatility cutoff for "switchable"

    /// One narrated finding before it is split into a `basic` line + `detail` item.
    private struct Finding {
        let key: String
        let headline: String
        let explanation: String
        let grade: String?
        let tags: [String]
        let evidence: [SuggestionEvidence]
        let salience: Double
        let confidence: String   // "high" / "medium" / "low"
    }

    /// A player's value + league percentile for one feature.
    private struct Ranked {
        let player: Player
        let name: String
        let value: Double
        let pctile: Double?
    }

    static func narrate(players: [Player], norms: LeagueNorms, label: LineupLabel,
                        creationClassificationEnabled: Bool = AppConfig.creationClassificationEnabled) -> LineupSuggestionReport {
        var basic: [SuggestionLine] = []
        var detail: [String: [SuggestionDetail]] = [:]

        func add(_ category: String, _ f: Finding?) {
            guard let f else { return }
            basic.append(SuggestionLine(key: f.key, category: category, text: f.headline,
                                        salience: f.salience, confidence: f.confidence))
            detail[category, default: []].append(SuggestionDetail(
                key: f.key, category: category, grade: f.grade, confidence: f.confidence,
                salience: f.salience, tags: f.tags, evidence: f.evidence,
                suggestion: f.headline, explanation: f.explanation))
        }

        add("offense", spacing(players, norms))
        add("offense", creation(players, norms, creationClassificationEnabled: creationClassificationEnabled))
        add("defense", rimProtection(players, norms))
        add("defense", switchability(players, norms))
        add("structure", structureLine(players, norms, label))

        // Strongest headline first.
        basic.sort { ($0.salience ?? 0) > ($1.salience ?? 0) }
        return LineupSuggestionReport(basic: basic, detail: detail)
    }

    // MARK: - Findings

    private static func spacing(_ players: [Player], _ norms: LeagueNorms) -> Finding? {
        let shooters = ranked(players, "fg3_pct", norms)
        guard !shooters.isEmpty else { return nil }

        // A spacing tax (a cold shooter) is the most actionable finding — surface it first.
        let cold = shooters.filter { ($0.pctile ?? 1) < coldPctile }
        if let worst = cold.min(by: { $0.value < $1.value }) {
            let threePar = worst.player.lineupFeatures?.three_par ?? 0
            let ev = [SuggestionEvidence(player: worst.name, stat: "3PT%", value: pctOf(worst.value),
                                         pct: pctStr(worst.pctile), sample: nil)]
            if threePar < lowVolumeThreePar {
                // Low volume -> untested, not a proven liability (conservative-negative).
                return Finding(
                    key: "spacing", headline: "Spacing question — \(worst.name) rarely shoots from deep; untested as a floor-spacer.",
                    explanation: "\(worst.name) takes very few threes, so their \(pctOf(worst.value)) clip is a small sample — treat the spacing as unproven, not bad. Give them room to prove it or run them as a screener/cutter.",
                    grade: "Average", tags: ["Non-shooter (untested)"], evidence: ev,
                    salience: 0.7, confidence: "low")
            }
            return Finding(
                key: "spacing", headline: "Clogged paint — \(worst.name) doesn't stretch it (\(pctOf(worst.value)) from three); defenses sag.",
                explanation: "\(worst.name) hits just \(pctOf(worst.value)) from deep (\(pctStr(worst.pctile) ?? "low") percentile) on real volume, so their defender helps off. Park them in the dunker spot and let the other four space.",
                grade: "Poor", tags: ["Clogged paint", "Non-shooter"], evidence: ev,
                salience: 0.7, confidence: "high")
        }

        // No cold shooter -> if multiple are live ON VOLUME, call out the spacing
        // strength. The volume gate keeps a 2-for-4 fluke from being named the lead
        // shooter (symmetry with the cold-shooter gate).
        let hot = shooters
            .filter { ($0.pctile ?? 0) >= hotPctile && ($0.player.lineupFeatures?.three_par ?? 0) >= lowVolumeThreePar }
            .sorted { $0.value > $1.value }
        if hot.count >= 2 {
            let lead = hot[0]
            let ev = hot.prefix(3).map { SuggestionEvidence(player: $0.name, stat: "3PT%", value: pctOf($0.value),
                                                            pct: pctStr($0.pctile), sample: nil) }
            return Finding(
                key: "spacing", headline: "Knockdown shooting — \(lead.name) (\(pctOf(lead.value))) leads \(hot.count) live shooters; attack closeouts.",
                explanation: "\(hot.count) players convert at or above league from three (led by \(lead.name) at \(pctOf(lead.value))). Defenses can't sag — play 5-out and drive-and-kick into the corners.",
                grade: "Good", tags: ["Knockdown shooters", "Spacing"], evidence: ev,
                salience: 0.6, confidence: "high")
        }
        return nil
    }

    private static func creation(_ players: [Player], _ norms: LeagueNorms,
                                  creationClassificationEnabled: Bool = AppConfig.creationClassificationEnabled) -> Finding? {
        let creators = ranked(players, "box_creation", norms).sorted { $0.value > $1.value }
        guard let top = creators.first else { return nil }
        let usgRank = ranked(players, "usg", norms)
        let leadUsers = usgRank.filter { ($0.pctile ?? 0) >= highUsagePctile }.sorted { $0.value > $1.value }

        if leadUsers.count >= 2 {
            let a = leadUsers[0], b = leadUsers[1]
            let ev = [a, b].map { SuggestionEvidence(player: $0.name, stat: "usage", value: pctOf($0.value),
                                                     pct: pctStr($0.pctile), sample: nil) }
            guard creationClassificationEnabled else {
                return Finding(
                    key: "creation", headline: "Two lead creators — \(a.name) and \(b.name) both need the ball; stagger them.",
                    explanation: "\(a.name) (\(pctOf(a.value)) usage) and \(b.name) (\(pctOf(b.value)) usage) are both high-usage initiators. Stagger their minutes or play one off-ball so the possessions don't collide.",
                    grade: "Average", tags: ["Ball-dominant", "Creation overlap"], evidence: ev,
                    salience: 0.55, confidence: "high")
            }
            let shareA = CreationClassifier.Share(value: a.player.lineupFeatures?.creation_volume,
                                                  src: a.player.lineupFeatures?.creation_share_src)
            let shareB = CreationClassifier.Share(value: b.player.lineupFeatures?.creation_volume,
                                                  src: b.player.lineupFeatures?.creation_share_src)
            let cls = CreationClassifier.classify(shareA, shareB, pins: norms.creationPins)
            return creationFinding(a: a, b: b, ev: ev, cls: cls, pins: norms.creationPins)
        }
        if (top.pctile ?? 0) >= highUsagePctile {
            let ev = [SuggestionEvidence(player: top.name, stat: "box creation", value: round1(top.value),
                                         pct: pctStr(top.pctile), sample: nil)]
            return Finding(
                key: "creation", headline: "\(top.name) runs the show (\(round1(top.value)) box creation).",
                explanation: "\(top.name) is the clear engine (\(round1(top.value)) box creation, \(pctStr(top.pctile) ?? "high") percentile). Build actions through them and surround with movement.",
                grade: "Good", tags: ["Primary creator", "Floor general"], evidence: ev,
                salience: 0.5, confidence: "high")
        }
        // No real initiator on the floor. Only assert this absence when most of the
        // five were actually measured for creation (don't claim "no initiator" off a
        // sparse subset that might omit the real engine).
        let creationCovered = players.filter {
            $0.lineupFeatures?.value("box_creation") != nil || $0.lineupFeatures?.value("usg") != nil
        }.count
        guard creationCovered >= 3 else { return nil }
        return Finding(
            key: "creation", headline: "Creation by committee — no primary initiator; lean on ball movement.",
            explanation: "Nobody on this five is a high-usage creator, so half-court offense can bog down. Generate advantages with off-ball screens and quick swing passes rather than isolation.",
            grade: "Average", tags: ["No initiator"], evidence: [],
            salience: 0.45, confidence: "medium")
    }

    private static func creationFinding(a: Ranked, b: Ranked, ev: [SuggestionEvidence],
                                        cls: CreationClassifier.Class, pins: CreationPins?) -> Finding? {
        switch cls {
        case .dual_initiator:
            let aVol = a.player.lineupFeatures?.creation_volume
            let bVol = b.player.lineupFeatures?.creation_volume
            let gap = abs((aVol ?? 0) - (bVol ?? 0))
            let mean = ((aVol ?? 0) + (bVol ?? 0)) / 2
            return Finding(
                key: "creation",
                headline: "\(a.name) and \(b.name) hold near-even team-assist shares on the floor, averaging above the league mid-band.",
                explanation: "\(a.name) (\(round2(aVol))) and \(b.name) (\(round2(bVol))) average \(round2(mean)) in on-court team-assist share — above the league mid-band (\(pinStr(pins?.mu))) — with a near-even split: the gap (\(pinStr(gap))) is within the league close-pair pin (\(pinStr(pins?.gapLow))). Observation from season assist-share data, not a lineup recommendation.",
                grade: "Average", tags: ["Near-even assist shares"], evidence: ev,
                salience: 0.55, confidence: "high")
        case .connector_scorer:
            let aVol = a.player.lineupFeatures?.creation_volume ?? 0
            let bVol = b.player.lineupFeatures?.creation_volume ?? 0
            let (connector, scorer, h, l) = aVol >= bVol ? (a, b, aVol, bVol) : (b, a, bVol, aVol)
            // Amendment A2: display the 3dp gap itself — the 2dp member shares alone
            // can visibly contradict the pin comparison (0.34-0.16=0.18 vs 0.182).
            // "unrounded" marks the gap as computed pre-rounding (the 2dp members
            // need not subtract to it); "meets or exceeds" stays true at the
            // inclusive gap == divergence boundary.
            let gap = h - l
            return Finding(
                key: "creation",
                headline: "\(connector.name) accounts for a much larger share of team assists than \(scorer.name).",
                explanation: "\(connector.name)'s on-court team-assist share (\(round2(h))) sits well above \(scorer.name)'s (\(round2(l))) — the unrounded gap (\(pinStr(gap))) meets or exceeds the league divergence pin (\(pinStr(pins?.divergence))). Observation from season assist-share data, not a lineup recommendation.",
                grade: "Good", tags: ["Higher assist share"], evidence: ev,
                salience: 0.55, confidence: "high")
        case .collision:
            let aVol = a.player.lineupFeatures?.creation_volume
            let bVol = b.player.lineupFeatures?.creation_volume
            let gap = abs((aVol ?? 0) - (bVol ?? 0))
            let mean = ((aVol ?? 0) + (bVol ?? 0)) / 2
            return Finding(
                key: "creation",
                headline: "\(a.name) and \(b.name) average below the league mid-band in team-assist share, with no divergence-clearing gap.",
                explanation: "\(a.name) (\(round2(aVol))) and \(b.name) (\(round2(bVol))) average \(round2(mean)) in on-court team-assist share — below the league mid-band (\(pinStr(pins?.mu))) — and the gap between them (\(pinStr(gap))) does not clear the league divergence pin (\(pinStr(pins?.divergence))). Observation from season assist-share data, not a lineup recommendation.",
                grade: "Average", tags: ["Below mid-band (pair average)"], evidence: ev,
                salience: 0.55, confidence: "high")
        case .neutral:
            return nil
        }
    }

    private static func rimProtection(_ players: [Player], _ norms: LeagueNorms) -> Finding? {
        let blk = ranked(players, "blk_pct", norms)
        let rimD = ranked(players, "rim_def_delta", norms)   // positive = opponents held below normal at the rim
        guard !blk.isEmpty || !rimD.isEmpty else { return nil }

        // Primary: a real shot-blocker.
        if let anchor = blk.max(by: { ($0.pctile ?? 0) < ($1.pctile ?? 0) }), (anchor.pctile ?? 0) >= anchorBlkPctile {
            let ev = [SuggestionEvidence(player: anchor.name, stat: "block rate", value: pctOf(anchor.value),
                                         pct: pctStr(anchor.pctile), sample: nil)]
            return Finding(
                key: "rim_protection", headline: "\(anchor.name) anchors the rim (\(pctOf(anchor.value)) block rate); funnel drives into them.",
                explanation: "\(anchor.name) protects the basket (\(pctStr(anchor.pctile) ?? "elite") percentile block rate). Build the defense to send drives at them and let the perimeter pressure up top.",
                grade: "Good", tags: ["Rim protector"], evidence: ev,
                salience: 0.62, confidence: "high")
        }
        // Secondary: a strong rim DEFENDER without the blocks (holds opponents below average at the rim).
        if let wall = rimD.max(by: { ($0.pctile ?? 0) < ($1.pctile ?? 0) }), (wall.pctile ?? 0) >= rimDefPctile {
            let ev = [SuggestionEvidence(player: wall.name, stat: "rim defense", value: nil,
                                         pct: pctStr(wall.pctile), sample: nil)]
            return Finding(
                key: "rim_protection", headline: "\(wall.name) walls up the rim — opponents finish worse at the basket against them.",
                explanation: "\(wall.name) doesn't rack up blocks but holds opponents below their expected rim conversion (\(pctStr(wall.pctile) ?? "high") percentile). Funnel drives their way and contest straight up.",
                grade: "Good", tags: ["Rim deterrent"], evidence: ev,
                salience: 0.6, confidence: "high")
        }
        // Neither a blocker nor a rim wall. State the absence plainly only when ALL
        // five were actually measured (rim metrics are often nil for guards/wings);
        // otherwise hedge it as tentative so a dropped record can't masquerade as a
        // confirmed hole.
        let rimCovered = players.filter {
            $0.lineupFeatures?.value("blk_pct") != nil || $0.lineupFeatures?.value("rim_def_delta") != nil
        }.count
        let full = rimCovered == players.count
        return Finding(
            key: "rim_protection",
            headline: full
                ? "No rim protection — no plus shot-blocker or rim deterrent; teams will attack the basket."
                : "Thin rim protection — no rim deterrent among the players we can measure.",
            explanation: full
                ? "None of the five rates as a real rim deterrent, so opponents can get downhill. Defend in a drop or wall up early, and crash the defensive glass since blocks won't bail you out."
                : "No measured rim deterrent here, but a player or two lack tracking data — treat it as a likely soft spot, not a certainty. Defend in a drop and crash the defensive glass.",
            grade: "Poor", tags: ["No rim protection"], evidence: [],
            salience: 0.6, confidence: full ? "high" : "low")
    }

    private static func switchability(_ players: [Player], _ norms: LeagueNorms) -> Finding? {
        let vers = ranked(players, "versatility", norms)
        guard vers.count >= 3 else { return nil }
        let switchable = vers.filter { ($0.pctile ?? 0) >= switchPctile }.sorted { $0.value > $1.value }
        if switchable.count >= 3 {
            let names = switchable.prefix(2).map(\.name).joined(separator: " and ")
            // "switch 1-4" presupposes 4 observed versatile defenders; avoid that
            // over-claim when fewer than all five were measured.
            let full = vers.count == players.count
            let ev = switchable.prefix(2).map { SuggestionEvidence(player: $0.name, stat: "versatility",
                                                                   value: nil, pct: pctStr($0.pctile), sample: nil) }
            return Finding(
                key: "switchability", headline: "Switchable — \(names) can guard multiple spots; switch most actions and stay home.",
                explanation: "At least three players grade as versatile defenders, so you can switch most screens without creating a mismatch. Switch and keep bodies attached.",
                grade: "Good", tags: ["Switchable"], evidence: ev,
                salience: 0.45, confidence: full ? "high" : "medium")
        }
        if let weak = vers.min(by: { $0.value < $1.value }), (weak.pctile ?? 1) < 0.3 {
            // A single-player negative: emit at LOW confidence so the UI shows the
            // "tentative" caption (no per-player minutes field exists to gate on).
            let ev = [SuggestionEvidence(player: weak.name, stat: "versatility", value: nil,
                                         pct: pctStr(weak.pctile), sample: nil)]
            return Finding(
                key: "switchability", headline: "Switch target — \(weak.name) can be hunted in space; scheme around the mismatch.",
                explanation: "\(weak.name) grades as a below-average switch defender, so opponents may target them in pick-and-roll. Pre-switch, hedge, or hide them on a low-usage player — treat this as a tendency, not a certainty.",
                grade: "Average", tags: ["Switch target"], evidence: ev,
                salience: 0.4, confidence: "low")
        }
        return nil
    }

    private static func structureLine(_ players: [Player], _ norms: LeagueNorms, _ label: LineupLabel) -> Finding? {
        guard !label.isEmpty else { return nil }
        let heights = players.compactMap { $0.lineupFeatures?.height_in }
        let note: String
        if let avg = mean(heights) {
            if avg >= 79.5 {
                note = "oversized across the board — play through size and own the glass"
            } else if avg <= 77.0 {
                note = "small and switchable — push pace and spread it, but watch the defensive glass"
            } else {
                note = "balanced size — flexible on both ends"
            }
        } else {
            note = "a balanced look"
        }
        return Finding(
            key: "typology", headline: "\(label.archetypeLabel) — \(note).",
            explanation: "This five reads as a \(label.archetypeLabel.lowercased()) group: \(note). Lean into that identity rather than fighting it.",
            grade: nil, tags: [], evidence: [],
            salience: 0.5, confidence: "high")
    }

    // MARK: - Helpers

    private static func ranked(_ players: [Player], _ feature: String, _ norms: LeagueNorms) -> [Ranked] {
        players.compactMap { p in
            guard let v = p.lineupFeatures?.value(feature) else { return nil }
            return Ranked(player: p, name: p.name, value: v, pctile: norms.percentile(v, feature: feature))
        }
    }

    /// "35%" for an already-percent feature value (fg3_pct/blk_pct/usg are 0..100).
    private static func pctOf(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    /// "68th" league percentile, or nil when norms lack the feature.
    private static func pctStr(_ p: Double?) -> String? {
        guard let p else { return nil }
        return "\(Int((p * 100).rounded()))th"
    }

    private static func round1(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Two-decimal display for a creation_share Double?; falls back to "—".
    private static func round2(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f", v)
    }

    /// Three-decimal display for a pin Double?; e.g. "0.576". Falls back to "—".
    private static func pinStr(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.3f", v)
    }

    private static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}
