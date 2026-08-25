import Foundation

/// How subjects are classified (spec §14). `totalOrder` = rank 1…N (bijective).
/// `tiers` = each subject → one reusable tier label. `uniqueLabels` = each label
/// used once (bijective; e.g. START/BENCH/CUT).
nonisolated enum ClassificationMode: String, Codable, Equatable {
    case totalOrder, tiers, uniqueLabels

    /// Bijective modes require one subject per destination (and equal counts).
    var isBijective: Bool { self != .tiers }
}

/// A classification game's configuration. Subjects are the top `candidatePoolSize`
/// players by rating, from which `subjectCount` are drawn (seeded) — so the set is
/// recognizable and has a real model order to score against.
nonisolated struct ClassificationConfig: Codable, Equatable {
    let mode: ClassificationMode
    let labels: [String]        // tiers/uniqueLabels: the label names (best→worst). totalOrder: [].
    let subjectCount: Int
    let candidatePoolSize: Int

    /// Number of destination buckets: ranks (=subjectCount) for totalOrder,
    /// labels.count for tiers/uniqueLabels.
    var destinationCount: Int {
        mode == .totalOrder ? subjectCount : labels.count
    }

    /// Human label for a destination index (0-based).
    func destinationLabel(_ index: Int) -> String {
        switch mode {
        case .totalOrder: return "\(index + 1)"
        case .tiers, .uniqueLabels:
            return index >= 0 && index < labels.count ? labels[index] : "\(index + 1)"
        }
    }
}

/// A classification game (self-contained; NOT the roster `GameDefinition`).
nonisolated struct ClassificationDefinition: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let config: ClassificationConfig
}
