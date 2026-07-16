import Foundation

/// Per-feature league distribution: mean, std, and the sorted raw values used
/// for the mid-rank percentile. All optional so a partially-populated norms doc
/// still decodes.
struct FeatureNorm: Codable, Equatable, Hashable {
    let mean: Double?
    let std: Double?
    let sorted: [Double]?
}

/// Calibrated thresholds for creation-pair classification (spec 1.2).
/// Decoded from the `creationPins` top-level key of the leagueNorms/2025-26 doc.
/// Missing or partial -> the whole struct is nil (fail-closed).
struct CreationPins: Codable, Equatable {
    let version: Int
    let source: String
    let initiator: Double
    let divergence: Double
    let season: String
}

/// League norms for one season (the singleton `leagueNorms/2025-26` doc). Maps
/// each feature name to its `FeatureNorm`. Provides the two primitives
/// (`percentile`, `zscore`) and the per-player lookups (`percentile`,
/// `zscore`) the labeling engine ranks against — copied verbatim (same
/// math/conventions) from scripts/lineup_labeling/norms.py.
struct LeagueNorms: Equatable {
    let byFeature: [String: FeatureNorm]
    let creationPins: CreationPins?

    init(byFeature: [String: FeatureNorm], creationPins: CreationPins? = nil) {
        self.byFeature = byFeature
        self.creationPins = creationPins
    }

    // MARK: - Primitives (mirror norms.py)

    /// League-relative rank of `value` within `sortedValues`, in [0, 1], using
    /// the mid-rank (Hazen) convention: (#below + 0.5 * #equal) / n. Median of a
    /// symmetric odd-length vector is exactly 0.5; strictly above all → 1.0;
    /// strictly below all → 0.0. nil for a nil value or empty distribution.
    nonisolated static func percentile(_ value: Double?, _ sortedValues: [Double]?) -> Double? {
        guard let value, let sortedValues, !sortedValues.isEmpty else { return nil }
        let n = Double(sortedValues.count)
        var below = 0.0
        var equal = 0.0
        for v in sortedValues {
            if v < value { below += 1 }
            else if v == value { equal += 1 }
        }
        return (below + 0.5 * equal) / n
    }

    /// (value - mean) / std. nil for a nil value or non-positive std.
    nonisolated static func zscore(_ value: Double?, _ mean: Double?, _ std: Double?) -> Double? {
        guard let value, let std, std > 0 else { return nil }
        return (value - (mean ?? 0)) / std
    }

    // MARK: - Per-feature lookups

    /// League percentile (0..1) of a raw feature `value`. nil when there is no
    /// distribution for the feature or the value is nil.
    nonisolated func percentile(_ value: Double?, feature: String) -> Double? {
        guard let value else { return nil }
        guard let fnorm = byFeature[feature] else { return nil }
        return Self.percentile(value, fnorm.sorted)
    }

    /// League z-score of a raw feature `value`. nil when there is no
    /// distribution for the feature or the value is nil.
    nonisolated func zscore(_ value: Double?, feature: String) -> Double? {
        guard let value else { return nil }
        guard let fnorm = byFeature[feature] else { return nil }
        return Self.zscore(value, fnorm.mean, fnorm.std)
    }
}

// MARK: - Decoding the Firestore singleton doc

extension LeagueNorms: Codable {
    /// The uploaded `leagueNorms/2025-26` doc is
    /// `{ "season": "2025-26", "features": { <feature>: {mean,std,sorted} } }`
    /// (see scripts/upload_lineup_features.py `build_norms_payload`). Decode the
    /// nested `features` map when present; otherwise fall back to treating the
    /// whole document as a flat `{feature: {mean,std,sorted}}` map.
    init(from decoder: Decoder) throws {
        // Try the wrapped {season, features} shape first.
        if let keyed = try? decoder.container(keyedBy: WrapperKeys.self),
           let features = try? keyed.decode([String: FeatureNorm].self, forKey: .features) {
            let pins = try? keyed.decode(CreationPins.self, forKey: .creationPins)
            self.init(byFeature: features, creationPins: pins)
            return
        }
        // Fall back to a flat {feature: {mean,std,sorted}} map, ignoring any
        // scalar metadata keys (e.g. "season") that aren't a FeatureNorm.
        let flat = try decoder.singleValueContainer()
        if let raw = try? flat.decode([String: FeatureNorm].self) {
            self.init(byFeature: raw, creationPins: nil)
        } else {
            let dyn = try decoder.container(keyedBy: DynamicKey.self)
            var out: [String: FeatureNorm] = [:]
            for key in dyn.allKeys where key.stringValue != "season" {
                if let fn = try? dyn.decode(FeatureNorm.self, forKey: key) {
                    out[key.stringValue] = fn
                }
            }
            self.init(byFeature: out, creationPins: nil)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WrapperKeys.self)
        try c.encode(byFeature, forKey: .features)
        try c.encodeIfPresent(creationPins, forKey: .creationPins)
    }

    private enum WrapperKeys: String, CodingKey {
        case season, features, creationPins
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
