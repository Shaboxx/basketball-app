import Foundation
import FirebaseFirestore

struct OwnedPicks: Codable, Identifiable {
    @DocumentID var docId: String?
    let teamId: String
    let picks: [Pick]
    let pickCount: Int?

    var id: String { teamId }
}
