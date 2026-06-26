import Foundation
import Combine

/// Loads `meta/dataHealth` and exposes each feed's last-refresh time + staleness,
/// mirroring the server-side watchdog's cadences (scripts/data_health.py).
@MainActor
final class DataHealthViewModel: ObservableObject {
    @Published var health: DataHealth?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard health == nil else { return }
        await reload()
    }

    func reload() async {
        // Keep last-known-good on a transient failure (mirrors the other VMs).
        if let h = try? await service.fetchDataHealth() { health = h }
    }

    struct Feed: Identifiable {
        let id: String
        let label: String
        let updatedAt: Date?
        let maxAge: TimeInterval
        /// Stale (or unknown) when older than its expected refresh cadence.
        var isStale: Bool {
            guard let updatedAt else { return true }
            return Date().timeIntervalSince(updatedAt) > maxAge
        }
    }

    private static let day: TimeInterval = 86_400

    var feeds: [Feed] {
        [
            Feed(id: "roster", label: "Rosters", updatedAt: health?.rosterUpdatedAt, maxAge: 2 * Self.day),
            Feed(id: "contracts", label: "Contracts", updatedAt: health?.contractsUpdatedAt, maxAge: 10 * Self.day),
            Feed(id: "picks", label: "Draft picks", updatedAt: health?.picksUpdatedAt, maxAge: 10 * Self.day),
        ]
    }

    var anyStale: Bool { feeds.contains { $0.isStale } }
}
