import Foundation

struct Team: Codable, Identifiable, Hashable {
    var docId: String? = nil
    let teamId: String
    let fullName: String
    let city: String
    let name: String
    let conference: String
    let division: String

    // The optional local document identity is outside the JSON payload.
    // The stable teamId supplies Identifiable conformance.
    enum CodingKeys: String, CodingKey {
        case teamId, fullName, city, name, conference, division
    }

    var id: String { teamId }
}
