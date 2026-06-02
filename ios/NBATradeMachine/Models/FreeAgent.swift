import Foundation

/// 2026 offseason free agent. Used by the "Sign Player" sheet in offseason
/// mode. Decoded from `free-agents.json` (bundled). All currency fields
/// are dollars. The expected salary anchors the soft warning band — same
/// scaling as `ResignContractSheet`.
struct FreeAgent: Codable, Identifiable, Hashable {
    let id: String              // slug
    let name: String
    let position: String
    let kind: TradeMachineViewModel.FreeAgentKind
    let priorTeamId: String?
    /// Best-guess market value. The signing sheet centers the soft window
    /// here. When the bundled data omits it, the field falls back to the
    /// hard minimum so the user always sees a legal default.
    let expectedSalary: Int?
    /// CBA min for this FA. Defaults to the veteran minimum used by the
    /// re-sign sheet if absent.
    let minSalary: Int?
    /// CBA max for this FA at the player tier they qualify for.
    let maxSalary: Int?
    /// Optional headshot slug — separate so the bundled file can omit it
    /// for prospects without imagery.
    let slug: String?
}

enum FreeAgentsService {
    /// Loads the bundled `free-agents.json` resource. Returns an empty
    /// list when the file is missing or malformed — the sheet shows the
    /// empty state and the rest of offseason mode keeps working.
    static func load() -> [FreeAgent] {
        guard let url = Bundle.main.url(forResource: "free-agents", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([FreeAgent].self, from: data)
        } catch {
            return []
        }
    }
}
