import Foundation
import FirebaseFirestore

struct Player: Codable, Identifiable, Hashable {
    @DocumentID var docId: String?
    let slug: String
    let name: String
    let teamId: String
    let position: String
    let heightInches: Int?
    let weightLbs: Int?
    let birthdate: String?       // ISO-8601 "YYYY-MM-DD"
    let primaryRole: String?
    let secondaryRole: String?
    let defensiveRole: String?
    let salaryY1: Int?
    let salaryY2: Int?
    let salaryY3: Int?
    let salaryY4: Int?

    // CBA Phase 1 fields (spec §4.3). All optional — old docs without CBA
    // data decode as nil.
    let yos: Int?
    let standardMax: Int?
    let minSalary: Int?
    let supermaxEligible: Bool?
    let nextContractMax: Int?
    let nextContractMaxBasis: String?
    let maxTierPct: Int?
    let higherMaxCriteriaMet: Bool?
    let supermaxPath: String?
    let contractFinalYearSalary: Int?
    let contractFinalYearSeasonEnd: Int?
    let cbaSeason: String?
    let cbaUpdatedAt: Date?

    // Explicit CodingKeys excludes `docId` so JSONDecoder (and Firestore's
    // decoder) don't look for it in the document payload. Firestore populates
    // @DocumentID out-of-band from the document reference.
    // IMPORTANT: every stored property of `Player` except `@DocumentID docId`
    // MUST be listed below. A property missing from this enum will silently
    // decode as nil (or fail to encode) without any compile-time warning.
    enum CodingKeys: String, CodingKey {
        case slug, name, teamId, position
        case heightInches, weightLbs, birthdate
        case primaryRole, secondaryRole, defensiveRole
        case salaryY1, salaryY2, salaryY3, salaryY4
        case yos, standardMax, minSalary, supermaxEligible
        case nextContractMax, nextContractMaxBasis, maxTierPct, higherMaxCriteriaMet
        case supermaxPath, contractFinalYearSalary, contractFinalYearSeasonEnd
        case cbaSeason, cbaUpdatedAt
    }

    var id: String { docId ?? slug }
    var currentSalary: Int { salaryY1 ?? 0 }

    var headshotPath: String { "headshots/\(slug).png" }

    var heightDisplay: String {
        guard let inches = heightInches else { return "-" }
        return "\(inches / 12)'\(inches % 12)\""
    }

    func salary(forSeasonOffset offset: Int) -> Int {
        switch offset {
        case 0: return salaryY1 ?? 0
        case 1: return salaryY2 ?? 0
        case 2: return salaryY3 ?? 0
        case 3: return salaryY4 ?? 0
        default: return 0
        }
    }

    func contractYearsRemaining(from offset: Int) -> Int {
        let years = [salaryY1, salaryY2, salaryY3, salaryY4]
        var count = 0
        for i in offset..<years.count {
            if (years[i] ?? 0) > 0 { count += 1 } else { break }
        }
        return count
    }
}
