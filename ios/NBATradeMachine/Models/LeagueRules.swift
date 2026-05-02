import Foundation
import FirebaseFirestore

struct LeagueRules: Codable {
    @DocumentID var docId: String?
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
