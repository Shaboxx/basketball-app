import Foundation

struct Pick: Identifiable, Hashable {
    let id: UUID
    let originatingTeamId: String
    let year: Int
    let round: Int
    let protection: PickProtection
    let projectedPosition: Int?
    let candidateSources: [String]?
    let selectionRule: PickSelectionRule?
    let isSwap: Bool
    let rawDescription: String?

    init(
        id: UUID = UUID(),
        originatingTeamId: String,
        year: Int,
        round: Int,
        protection: PickProtection = .unprotected,
        projectedPosition: Int? = nil,
        candidateSources: [String]? = nil,
        selectionRule: PickSelectionRule? = nil,
        isSwap: Bool = false,
        rawDescription: String? = nil
    ) {
        self.id = id
        self.originatingTeamId = originatingTeamId
        self.year = year
        self.round = round
        self.protection = protection
        self.projectedPosition = projectedPosition
        self.candidateSources = candidateSources
        self.selectionRule = selectionRule
        self.isSwap = isSwap
        self.rawDescription = rawDescription
    }

    var isComplex: Bool {
        candidateSources != nil || selectionRule != nil || isSwap
    }

    var shortLabel: String {
        let suffix = round == 1 ? "1st" : "2nd"
        let sourceText = candidateSources.map { sources -> String in
            let prefix = selectionRule?.shortPrefix ?? "One of"
            return "\(prefix) \(sources.joined(separator: "/"))"
        } ?? originatingTeamId
        var label = "\(sourceText) \(year) \(suffix)"
        if isSwap, candidateSources == nil { label += " (swap)" }
        if protection != .unprotected { label += " (\(protection.shortLabel))" }
        return label
    }
}

enum PickProtection: Hashable {
    case unprotected
    case top4Protected
    case top10Protected
    case lotteryProtected
    case other(String)

    var shortLabel: String {
        switch self {
        case .unprotected: return "Unprotected"
        case .top4Protected: return "Top-4 prot."
        case .top10Protected: return "Top-10 prot."
        case .lotteryProtected: return "Lottery prot."
        case .other(let label): return label
        }
    }

    static var pickerOptions: [PickProtection] {
        [.unprotected, .top4Protected, .top10Protected, .lotteryProtected]
    }

    init(rawId: String) {
        switch rawId {
        case "unprotected": self = .unprotected
        case "top4Protected": self = .top4Protected
        case "top10Protected": self = .top10Protected
        case "lotteryProtected": self = .lotteryProtected
        default: self = .other(rawId)
        }
    }
}

enum PickSelectionRule: String, Codable, Hashable {
    case mostFavorable
    case leastFavorable
    case secondMostFavorable
    case thirdMostFavorable
    case fourthMostFavorable
    case fifthMostFavorable
    case secondLeastFavorable
    case unspecified

    var shortPrefix: String {
        switch self {
        case .mostFavorable: return "Best of"
        case .leastFavorable: return "Worst of"
        case .secondMostFavorable: return "2nd best of"
        case .thirdMostFavorable: return "3rd best of"
        case .fourthMostFavorable: return "4th best of"
        case .fifthMostFavorable: return "5th best of"
        case .secondLeastFavorable: return "2nd worst of"
        case .unspecified: return "One of"
        }
    }

    var valueMultiplier: Double {
        switch self {
        case .mostFavorable: return 1.15
        case .leastFavorable: return 0.55
        case .secondMostFavorable: return 0.95
        case .thirdMostFavorable: return 0.75
        case .fourthMostFavorable: return 0.60
        case .fifthMostFavorable: return 0.50
        case .secondLeastFavorable: return 0.65
        case .unspecified: return 1.0
        }
    }
}

struct PickMovement: Identifiable, Hashable {
    let id: UUID
    let pick: Pick
    let fromTeamId: String
    let toTeamId: String

    init(id: UUID = UUID(), pick: Pick, fromTeamId: String, toTeamId: String) {
        self.id = id
        self.pick = pick
        self.fromTeamId = fromTeamId
        self.toTeamId = toTeamId
    }
}

extension Pick: Codable {
    private enum CodingKeys: String, CodingKey {
        case originatingTeamId, year, round, protection, projectedPosition
        case candidateSources, selectionRule, isSwap, rawDescription
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.originatingTeamId = try c.decode(String.self, forKey: .originatingTeamId)
        self.year = try c.decode(Int.self, forKey: .year)
        self.round = try c.decode(Int.self, forKey: .round)
        let protectionRaw = try c.decodeIfPresent(String.self, forKey: .protection) ?? "unprotected"
        self.protection = PickProtection(rawId: protectionRaw)
        self.projectedPosition = try c.decodeIfPresent(Int.self, forKey: .projectedPosition)
        self.candidateSources = try c.decodeIfPresent([String].self, forKey: .candidateSources)
        self.selectionRule = try c.decodeIfPresent(PickSelectionRule.self, forKey: .selectionRule)
        self.isSwap = try c.decodeIfPresent(Bool.self, forKey: .isSwap) ?? false
        self.rawDescription = try c.decodeIfPresent(String.self, forKey: .rawDescription)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(originatingTeamId, forKey: .originatingTeamId)
        try c.encode(year, forKey: .year)
        try c.encode(round, forKey: .round)
        try c.encode(protection.rawId, forKey: .protection)
        try c.encodeIfPresent(projectedPosition, forKey: .projectedPosition)
        try c.encodeIfPresent(candidateSources, forKey: .candidateSources)
        try c.encodeIfPresent(selectionRule, forKey: .selectionRule)
        if isSwap { try c.encode(true, forKey: .isSwap) }
        try c.encodeIfPresent(rawDescription, forKey: .rawDescription)
    }
}

extension PickProtection {
    nonisolated var rawId: String {
        switch self {
        case .unprotected: return "unprotected"
        case .top4Protected: return "top4Protected"
        case .top10Protected: return "top10Protected"
        case .lotteryProtected: return "lotteryProtected"
        case .other(let s): return s
        }
    }
}
