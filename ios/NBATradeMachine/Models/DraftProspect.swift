import Foundation

/// 2026 draft class entry. Decoded from `draft-2026.json` if bundled; the
/// draft sheet shows an empty state otherwise.
struct DraftProspect: Codable, Identifiable, Hashable {
    let id: String              // slug
    let name: String
    let position: String
    let school: String?
    /// Lower = better prospect. Drives the team-before simulation: prospects
    /// with rank below the user's pick slot are pre-claimed.
    let consensusRank: Int
    let slug: String?
}

/// Round-1 rookie scale slot salaries. Sourced from the 2025-26 CBA rookie
/// scale table; close enough for a sim — the real number depends on the
/// signing tier multiplier (80–120% of scale). Slot index 1-30 for round 1.
/// Round 2 uses the veteran minimum.
enum RookieScale {
    private static let firstRound: [Int: Int] = [
        1: 12_500_000, 2: 11_200_000, 3: 10_050_000, 4: 9_050_000, 5: 8_150_000,
        6: 7_350_000, 7: 6_650_000, 8: 6_000_000, 9: 5_450_000, 10: 4_950_000,
        11: 4_500_000, 12: 4_100_000, 13: 3_750_000, 14: 3_450_000, 15: 3_200_000,
        16: 2_975_000, 17: 2_800_000, 18: 2_650_000, 19: 2_525_000, 20: 2_415_000,
        21: 2_320_000, 22: 2_240_000, 23: 2_175_000, 24: 2_125_000, 25: 2_090_000,
        26: 2_060_000, 27: 2_035_000, 28: 2_015_000, 29: 2_000_000, 30: 1_990_000
    ]
    private static let secondRoundDefault = 1_300_000

    static func salary(forOverallSlot slot: Int, round: Int) -> Int {
        if round == 1, let v = firstRound[slot] { return v }
        return secondRoundDefault
    }
}

enum DraftService {
    static let defaultYear = 2026

    /// Bundled prospects in rank order; returns [] when missing or invalid.
    static func loadProspects(year: Int = defaultYear) -> [DraftProspect] {
        let name = "draft-\(year)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            let list = try JSONDecoder().decode([DraftProspect].self, from: data)
            return list.sorted { $0.consensusRank < $1.consensusRank }
        } catch {
            return []
        }
    }
}
