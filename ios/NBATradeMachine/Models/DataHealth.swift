import Foundation

/// Per-feed last-success timestamps from `meta/dataHealth`, stamped by the refresh
/// jobs (scripts/data_health.py) on every successful run. Backs the in-app
/// freshness indicator. Every field is optional so a partially-stamped doc still
/// decodes (Firestore `Timestamp` fields map to `Date`).
nonisolated struct DataHealth: Codable, Equatable {
    let rosterUpdatedAt: Date?
    let contractsUpdatedAt: Date?
    let picksUpdatedAt: Date?
    let rosterCount: Int?
    let contractsCount: Int?
    let picksCount: Int?
}
