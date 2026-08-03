import Foundation
import Combine

/// Loads the singleton `leagueCalendar/current` doc once at launch. When absent,
/// `calendar` stays nil and callers fall back to `AppConfig`/`fallbackSeason`.
@MainActor
final class LeagueCalendarViewModel: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var calendar: LeagueCalendar?

    private let service: FirestoreReading
    init(service: FirestoreReading = FirestoreService.shared) { self.service = service }

    func load() async {
        guard calendar == nil else { return }
        await reload()
    }

    func reload() async {
        // Keep last-known-good on a failed/missing fetch (foreground-refresh blip).
        if let c = try? await service.fetchLeagueCalendar() {
            calendar = c
        }
    }
}
