import Foundation
import Combine

/// Loads `meta/dataHealth` and exposes each feed's last-refresh time + staleness,
/// mirroring the server-side watchdog's cadences (scripts/data_health.py).
@MainActor
final class DataHealthViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var health: DataHealth?
    /// True when the last fetch threw (e.g. permission denied / offline) so we
    /// have no freshness data to judge from. Distinct from "the data is old" —
    /// we must not paint feeds as stale when we simply couldn't read the doc.
    @Published var loadFailed = false

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard health == nil else { return }
        await reload()
    }

    func reload() async {
        do {
            // A successful read may still return nil (doc missing / decode fail);
            // that's "unknown", not a hard error, so clear the failure flag.
            health = try await service.fetchDataHealth()
            loadFailed = false
        } catch {
            // Couldn't reach meta/dataHealth (permission denied, offline, ...).
            // Keep any last-known-good `health`; flag the failure so the UI says
            // "couldn't check" rather than falsely reporting every feed as stale.
            loadFailed = true
            print("[DataHealth] fetch failed: \(error)")
        }
    }

    /// A feed's freshness. `unknown` (no timestamp / read failed) is deliberately
    /// separate from `stale` (we have a timestamp and it's past its cadence) — the
    /// two must render differently so a failed read never masquerades as old data.
    enum FreshnessState { case fresh, stale, unknown }

    struct Feed: Identifiable {
        let id: String
        let label: String
        let updatedAt: Date?
        let maxAge: TimeInterval
        var state: FreshnessState {
            guard let updatedAt else { return .unknown }
            return Date().timeIntervalSince(updatedAt) > maxAge ? .stale : .fresh
        }
        var isStale: Bool { state == .stale }
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

    /// Overall banner state for the footer. `unavailable` means we couldn't read
    /// freshness at all (permission denied / offline / missing doc) — honest about
    /// not knowing, instead of claiming everything is current or stale.
    enum Status { case current, someStale, unavailable }
    var status: Status {
        guard health != nil else { return .unavailable }
        return anyStale ? .someStale : .current
    }
}
