import Foundation

/// CBA salary-cap exception used for a signing. Drives hard-cap derivation.
/// Hard-cap triggers are sourced from leagueRules.json `exceptions[*].useRestriction`
/// and `tradeRules.signAndTrade.acquiringTeamHardCapped` (= "first apron").
/// NOTE: leagueRules.json hard-caps BOTH MLE tiers at the first apron (the real
/// 2023 CBA puts the taxpayer MLE at the second apron); we follow the app's data.
enum ExceptionType: String, Codable, Hashable, CaseIterable {
    case capSpace, minimum, birdRights
    case nonTaxpayerMLE, taxpayerMLE, biAnnual, roomMLE
    case signAndTrade

    var label: String {
        switch self {
        case .capSpace: return "Cap Space"
        case .minimum: return "Minimum"
        case .birdRights: return "Bird Rights"
        case .nonTaxpayerMLE: return "Non-Taxpayer MLE"
        case .taxpayerMLE: return "Taxpayer MLE"
        case .biAnnual: return "Bi-Annual"
        case .roomMLE: return "Room MLE"
        case .signAndTrade: return "Sign-and-Trade"
        }
    }

    /// Using this exception hard-caps the team at the first apron for the season.
    var hardCapsAtFirstApron: Bool {
        switch self {
        case .nonTaxpayerMLE, .taxpayerMLE, .biAnnual, .signAndTrade: return true
        case .capSpace, .minimum, .birdRights, .roomMLE: return false
        }
    }
}

/// Apron a hard cap binds at. Only `.first` is produced in M2/M3.
enum HardCapApron: String, Codable, Hashable { case first, second }
