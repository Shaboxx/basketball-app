import Foundation
import FirebaseFirestore

struct Team: Codable, Identifiable, Hashable {
    @DocumentID var docId: String?
    let teamId: String
    let fullName: String
    let city: String
    let name: String
    let conference: String
    let division: String

    var id: String { teamId }
}
