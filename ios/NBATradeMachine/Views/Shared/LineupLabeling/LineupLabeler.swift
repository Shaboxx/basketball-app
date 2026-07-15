import Foundation

/// The fused descriptive verdict for a five-man lineup — the Swift analogue of
/// the dict returned by scripts/lineup_labeling/engine.py `label_lineup`.
nonisolated struct LineupLabel: Equatable {
    let archetype: String          // resolved single identity key
    let tags: [LineupTag]          // firing tags, category-ordered
    let enables: [String]          // union of firing tags' enables, minus nullified
    let strains: [String]          // archetype strains + firing tags' strains
    let strengths: [String]        // readable phrasing of the dominant enables
    let weaknesses: [String]       // readable phrasing of the dominant strains

    // SP-C: live capability magnitudes + formation viability + o/d quality
    // (ported from scripts/lineup_value/{synergy,formations,score}.py).
    let capabilityMagnitudes: [String: Double]   // spacing/pnr_fit/switchable/rim_protection/creation_redundancy
    let formationsViable: [String: Bool]         // five_out/switch_everything/two_big_drop/pnr_heavy
    let oQuality: Double
    let dQuality: Double

    /// Human-readable archetype name (e.g. "Five-Out"). Falls back to the raw
    /// key when unknown. Reads the master taxonomy flag to select V1 or V2 labels.
    var archetypeLabel: String {
        let map = AppConfig.archetypeTaxonomyV2
            ? LineupArchetypes.archetypeLabelsV2 : LineupArchetypes.archetypeLabelsV1
        return map[archetype] ?? archetype
    }

    /// True when no player carried a feature record (the engine abstained
    /// entirely). The view shows "unavailable" in this case.
    var isEmpty: Bool {
        archetype == "balanced" && tags.isEmpty && enables.isEmpty && strains.isEmpty
    }
}

/// Top-level lineup-labeling entry point — a faithful Swift port of
/// scripts/lineup_labeling/engine.py. Pure and deterministic: tags come out in
/// category order, and every derived list is de-duplicated while preserving
/// first-seen order, so the same input always yields identical output.
nonisolated enum LineupLabeler {

    /// Order-preserving de-duplication.
    private static func dedup(_ seq: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in seq where !seen.contains(x) {
            seen.insert(x)
            out.append(x)
        }
        return out
    }

    /// Tag keys ordered by category, then by registry insertion order within a
    /// category (mirrors engine._ordered_tags).
    private static func orderedTags(_ fired: [String]) -> [String] {
        let firedSet = Set(fired)
        var byCat: [String: [String]] = [:]
        for c in LineupTags.categoryOrder { byCat[c] = [] }
        for key in LineupTags.registryKeys where firedSet.contains(key) {
            if let cat = LineupTags.registry[key]?.category {
                byCat[cat, default: []].append(key)
            }
        }
        var ordered: [String] = []
        for c in LineupTags.categoryOrder { ordered.append(contentsOf: byCat[c] ?? []) }
        return ordered
    }

    private static func phraseStrengths(_ enables: [String]) -> [String] {
        enables.prefix(4).map { "Generates \($0)" }
    }

    private static func phraseWeaknesses(_ strains: [String]) -> [String] {
        strains.prefix(4).map { "Strains \($0)" }
    }

    /// Label a five-man lineup. `players` are read for their `lineupFeatures`;
    /// players missing a feature record abstain gracefully (their slot is nil).
    /// `impacts` carries each player's `thetaV2?.l2Signed` (same order as
    /// `players`).
    static func label(players: [Player], norms: LeagueNorms,
                      tier: String = "starters",
                      impacts: [Double?]) -> LineupLabel {
        let features: [LineupFeatures?] = players.map { $0.lineupFeatures }

        let fired = orderedTags(LineupTags.fireTags(features, norms))

        let archetype = LineupArchetypes.resolve(features, norms, tags: fired,
                                                  impacts: impacts, tier: tier)
        let strainMap = AppConfig.archetypeTaxonomyV2
            ? LineupArchetypes.archetypeStrainsV2 : LineupArchetypes.archetypeStrainsV1
        let archStrains = strainMap[archetype] ?? []

        // enables = union of firing tags' enables, minus those the archetype
        // (or a firing tag's own strain) nullifies.
        var rawEnables: [String] = []
        var rawTagStrains: [String] = []
        for key in fired {
            guard let meta = LineupTags.registry[key] else { continue }
            rawEnables.append(contentsOf: meta.enables)
            rawTagStrains.append(contentsOf: meta.strains)
        }

        let nullified = Set(archStrains).union(rawTagStrains)
        let enables = dedup(rawEnables.filter { !nullified.contains($0) })

        // strains = archetype strains + firing tags' strains (de-duped, stable).
        let strains = dedup(archStrains + rawTagStrains)

        let tagObjs: [LineupTag] = fired.compactMap { key in
            guard let meta = LineupTags.registry[key] else { return nil }
            return LineupTag(key: key, category: meta.category, label: meta.label,
                             isProxy: LineupTags.proxyTags.contains(key))
        }

        // SP-C: capability magnitudes + formation viability + o/d quality (mirrors score.py).
        let feats: [LineupFeatures] = features.compactMap { $0 }
        let mags = LineupSynergy.magnitudes(feats, norms)
        let ranked = impacts.compactMap { $0 }.sorted(by: >)
        let base = ranked.enumerated().reduce(0.0) { $0 + $1.element * pow(0.85, Double($1.offset)) }  // ror=0.85
        let off = ["spacing": 1.0, "pnr_fit": 0.1, "creation_redundancy": -1.0]   // _OFF_CAP × DEFAULT_COEFFS
        let def = ["switchable": 1.0, "rim_protection": 1.0]                       // _DEF_CAP × DEFAULT_COEFFS
        let oQuality = base + off.reduce(0.0) { $0 + $1.value * (mags[$1.key] ?? 0) }
        let dQuality = base + def.reduce(0.0) { $0 + $1.value * (mags[$1.key] ?? 0) }
        let nNonshooters = feats.filter { !LineupSynergy.isShooter($0, norms) }.count
        // drop anchor (z-form, mirrors score.py): above-average rim volume + below-median versatility
        let hasDropAnchor = feats.contains {
            (norms.zscore($0.value("rim_dfga_per36"), feature: "rim_dfga_per36") ?? 0) >= 0.2
            && (norms.zscore($0.value("versatility"), feature: "versatility") ?? 0) < 0.0
        }
        let formationsViable = LineupFormations.viable(mags, nNonshooters: nNonshooters, hasDropAnchor: hasDropAnchor)

        return LineupLabel(
            archetype: archetype,
            tags: tagObjs,
            enables: enables,
            strains: strains,
            strengths: phraseStrengths(enables),
            weaknesses: phraseWeaknesses(strains),
            capabilityMagnitudes: mags,
            formationsViable: formationsViable,
            oQuality: oQuality,
            dQuality: dQuality
        )
    }
}
