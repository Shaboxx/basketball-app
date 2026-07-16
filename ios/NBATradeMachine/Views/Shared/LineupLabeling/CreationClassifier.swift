import Foundation

/// Pure creation-pair classifier implementing spec 1.1 (v2) exactly.
/// nonisolated — the app target defaults to MainActor isolation;
/// pure logic must be nonisolated (repo convention).
nonisolated enum CreationClassifier {
    struct Share {
        let value: Double?
        let src: String?
    }

    enum Class: String, Equatable {
        case dual_initiator
        case connector_scorer
        case collision
        case neutral
    }

    /// Classify a creation-volume pair against calibrated league pins.
    /// V2 predicate (spec 1.1, order normative):
    /// Step 0 — fail-closed guards -> .neutral.
    /// Then with mean = (a+b)/2, gap = |a-b|:
    /// 1. connector_scorer iff gap >= divergence
    /// 2. neutral iff |mean - mu| < band  (STRICT <; edge belongs outside)
    /// 3. dual_initiator iff mean >= mu && gap <= gapLow  (both inclusive)
    /// 4. collision iff mean < mu
    /// 5. neutral otherwise (mean >= mu, gapLow < gap < divergence: contested mid-gap zone)
    nonisolated static func classify(_ a: Share, _ b: Share, pins: CreationPins?) -> Class {
        // --- Step 0: fail-closed guards ---
        guard let sa = a.value, let sb = b.value else { return .neutral }
        guard sa.isFinite, sb.isFinite else { return .neutral }
        guard sa >= 0, sa <= 1, sb >= 0, sb <= 1 else { return .neutral }
        guard let srcA = a.src, let srcB = b.src, srcA == srcB else { return .neutral }
        guard let pins else { return .neutral }
        guard pins.version == 2 else { return .neutral }
        guard pins.source == srcA else { return .neutral }
        guard let mu = pins.mu, let gapLow = pins.gapLow,
              let divergence = pins.divergence, let band = pins.band else { return .neutral }
        guard mu.isFinite, gapLow.isFinite, divergence.isFinite, band.isFinite else { return .neutral }
        guard mu >= 0, mu <= 1 else { return .neutral }
        guard gapLow >= 0, divergence >= 0, band >= 0 else { return .neutral }
        guard gapLow <= divergence else { return .neutral }

        // --- Steps 1-5 ---
        let mean = (sa + sb) / 2.0
        let gap = abs(sa - sb)

        if gap >= divergence { return .connector_scorer }
        if abs(mean - mu) < band { return .neutral }
        if mean >= mu && gap <= gapLow { return .dual_initiator }
        if mean < mu { return .collision }
        return .neutral
    }
}
