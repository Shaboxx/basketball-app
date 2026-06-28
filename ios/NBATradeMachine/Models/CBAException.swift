import Foundation

/// CBA salary-cap exception used for a signing. Drives hard-cap derivation.
/// Hard-cap aprons are sourced from leagueRules.json `exceptions[*].hardCapApron`
/// and `tradeRules.signAndTrade.acquiringTeamHardCapped` (= "first apron").
/// The taxpayer MLE hard-caps at the SECOND apron (CBA Art. VII §6(f); leagueRules
/// corrected 2026-06-13); the non-taxpayer MLE, bi-annual, and sign-and-trade cap
/// at the FIRST apron.
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

    /// The apron a team is hard-capped at for the season after using this exception,
    /// or nil if it triggers no hard cap. Taxpayer MLE binds at the SECOND apron; the
    /// non-taxpayer MLE / bi-annual / sign-and-trade bind at the FIRST apron.
    var hardCapApron: HardCapApron? {
        switch self {
        case .taxpayerMLE: return .second
        case .nonTaxpayerMLE, .biAnnual, .signAndTrade: return .first
        case .capSpace, .minimum, .birdRights, .roomMLE: return nil
        }
    }
}

/// Apron a hard cap binds at.
enum HardCapApron: String, Codable, Hashable { case first, second }
