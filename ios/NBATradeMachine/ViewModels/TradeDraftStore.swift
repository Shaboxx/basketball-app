import Foundation

/// A persistable snapshot of an in-progress trade (the fix for the Critical
/// "trade state destroyed on dismiss" — NAV-01). Holds the full `Trade` (teams
/// are Codable, players/picks re-resolve by id at render time) plus the
/// offseason overlays so a half-built multi-team trade survives an accidental
/// dismiss, rotation, or app kill.
struct TradeDraft: Codable {
    var trade: Trade
    var isOffseason: Bool
    var signedContracts: [String: TradeMachineViewModel.ReSignedContract]
    var signedFreeAgents: [String: [TradeMachineViewModel.SignedFreeAgent]]
    var draftedProspects: [String: [TradeMachineViewModel.DraftedProspect]]
    var savedAt: Date

    /// True when the draft holds real work worth restoring (a bare pair of
    /// seated teams with nothing moved is not worth a resume prompt).
    var hasWork: Bool {
        !trade.movements.isEmpty
            || !trade.pickMovements.isEmpty
            || trade.cashSent.values.contains { $0 > 0 }
            || !trade.waived.isEmpty
            || !trade.dismissed.isEmpty
            || !signedContracts.isEmpty
            || signedFreeAgents.values.contains { !$0.isEmpty }
            || draftedProspects.values.contains { !$0.isEmpty }
    }

    var teamCount: Int { trade.teams.count }
}

/// UserDefaults-backed single-slot store for the in-progress trade draft.
/// Mirrors `FantasyTeamStore`'s injectable-defaults seam so it's unit-testable.
struct TradeDraftStore {
    static let key = "tradeDraft.v1"
    var defaults: UserDefaults = .standard

    func save(_ draft: TradeDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func load() -> TradeDraft? {
        guard let data = defaults.data(forKey: Self.key),
              let draft = try? JSONDecoder().decode(TradeDraft.self, from: data)
        else { return nil }
        return draft
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    var hasDraft: Bool { defaults.data(forKey: Self.key) != nil }
}
