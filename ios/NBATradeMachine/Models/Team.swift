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

    // Explicit CodingKeys excludes `docId` so JSONDecoder (and Firestore's
    // decoder) don't look for it in the document payload — Firestore populates
    // @DocumentID out-of-band from the document reference. Mirrors `Player`.
    enum CodingKeys: String, CodingKey {
        case teamId, fullName, city, name, conference, division
    }

    var id: String { teamId }
}
