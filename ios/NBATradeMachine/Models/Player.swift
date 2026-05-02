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
    let primaryRole: String?
    let secondaryRole: String?
    let salaryY1: Int?
    let salaryY2: Int?
    let salaryY3: Int?
    let salaryY4: Int?

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
