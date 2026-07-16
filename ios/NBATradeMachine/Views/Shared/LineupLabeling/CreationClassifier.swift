import Foundation

/// Pure creation-pair classifier implementing spec 1.3 exactly.
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

    nonisolated static func classify(_ a: Share, _ b: Share, pins: CreationPins?) -> Class {
        guard let sa = a.value, let sb = b.value else { return .neutral }
        guard sa >= 0, sa <= 1, sb >= 0, sb <= 1 else { return .neutral }
        guard let srcA = a.src, let srcB = b.src, srcA == srcB else { return .neutral }
        guard let pins else { return .neutral }
        guard pins.version == 1 else { return .neutral }
        guard pins.source == srcA else { return .neutral }
        guard pins.initiator.isFinite, pins.divergence.isFinite, pins.divergence >= 0 else { return .neutral }

        let aAbove = sa >= pins.initiator
        let bAbove = sb >= pins.initiator
        if aAbove && bAbove { return .dual_initiator }
        let gap = abs(sa - sb)
        if aAbove != bAbove && gap >= pins.divergence { return .connector_scorer }
        if !aAbove && !bAbove { return .collision }
        return .neutral
    }
}
