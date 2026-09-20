import Foundation

struct LeagueRules: Codable {
    var docId: String? = nil
    let season: String
    let salaryCap: Int
    let taxLevel: Int
    let firstApron: Int
    let secondApron: Int

    enum CapTier: String, Comparable {
        case underCap = "Under Cap"
        case overCap = "Over Cap"
        case overTax = "Over Tax"
        case overFirstApron = "Over First Apron"
        case overSecondApron = "Over Second Apron"

        var level: Int {
            switch self {
            case .underCap: return 0
            case .overCap: return 1
            case .overTax: return 2
            case .overFirstApron: return 3
            case .overSecondApron: return 4
            }
        }

        static func < (lhs: CapTier, rhs: CapTier) -> Bool { lhs.level < rhs.level }
    }

    func tier(for totalSalary: Int) -> CapTier {
        if totalSalary >= secondApron { return .overSecondApron }
        if totalSalary >= firstApron { return .overFirstApron }
        if totalSalary >= taxLevel { return .overTax }
        if totalSalary >= salaryCap { return .overCap }
        return .underCap
    }
}

#if DEBUG
extension LeagueRules {
    /// Tiny cap so all modest test salaries — even a star-dumping team's
    /// post-trade total — stay in the over-cap tier, exercising the 125%/200%
    /// salary-matching band rather than the under-cap room path. Built via the
    /// memberwise init with a nil local document identity.
    static func testFixture(season: String = "2025-26",
                            salaryCap: Int = 1_000_000,
                            taxLevel: Int = 200_000_000,
                            firstApron: Int = 300_000_000,
                            secondApron: Int = 400_000_000) -> LeagueRules {
        LeagueRules(docId: nil, season: season, salaryCap: salaryCap,
                    taxLevel: taxLevel, firstApron: firstApron, secondApron: secondApron)
    }
}
#endif
