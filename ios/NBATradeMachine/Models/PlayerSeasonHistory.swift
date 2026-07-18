import Foundation

nonisolated struct PlayerSeasonHistory: Codable, Equatable {
    let slug: String
    let seasons: [SeasonRow]

    nonisolated struct SeasonRow: Codable, Equatable {
        let season: String
        let gp: Int?
        let min: Double?
        let box: Box
        let advanced: Advanced
        let injuryWindowDays: Int?
    }

    nonisolated struct Box: Codable, Equatable {
        let pts, reb, ast, stl, blk, tov: Double?
        let fgPct, fg3Pct, ftPct: Double?
    }

    nonisolated struct Advanced: Codable, Equatable {
        // tsPct/efgPct/usgPct/oreb/dreb from crafted; per/bpm/astPct from BBRef;
        // netRating from advanced-history. All optional -> dash.
        let tsPct, efgPct, usgPct, netRating, per, bpm, astPct, oreb, dreb: Double?
    }
}
