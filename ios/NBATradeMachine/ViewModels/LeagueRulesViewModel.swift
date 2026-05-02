import Foundation
import Combine

@MainActor
final class LeagueRulesViewModel: ObservableObject {
    @Published var rules: LeagueRules?

    func load() async {
        guard rules == nil else { return }
        rules = try? await FirestoreService.shared.fetchLeagueRules()
    }
}
