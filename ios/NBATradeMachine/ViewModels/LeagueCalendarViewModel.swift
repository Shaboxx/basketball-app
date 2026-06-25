import Foundation
import Combine

/// Loads the singleton `leagueCalendar/current` doc once at launch. When absent,
/// `calendar` stays nil and callers fall back to `AppConfig`/`fallbackSeason`.
@MainActor
final class LeagueCalendarViewModel: ObservableObject {
    @Published var calendar: LeagueCalendar?

    func load() async {
        guard calendar == nil else { return }
        await reload()
    }

    func reload() async {
        // Keep last-known-good on a failed/missing fetch (foreground-refresh blip).
        if let c = try? await FirestoreService.shared.fetchLeagueCalendar() {
            calendar = c
        }
    }
}
