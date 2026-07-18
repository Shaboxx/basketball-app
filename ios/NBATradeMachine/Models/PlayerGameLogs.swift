import Foundation

nonisolated struct PlayerGameLogSeason: Codable, Equatable {
    let slug: String
    let season: String
    let games: [GameLine]
}

nonisolated struct GameLine: Codable, Equatable {
    let gameId: String
    let date: String
    let teamId: String?
    let opp: String?
    let home: Bool?
    let wl: String?
    let min: Double?
    let pts, reb, ast, stl, blk, tov, oreb, dreb, pf: Int?
    let fgm, fga, fg3m, fg3a, ftm, fta, plusMinus: Int?
    let missed: Bool

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        gameId = try c.decode(String.self, forKey: .gameId)
        date = try c.decode(String.self, forKey: .date)
        teamId = try c.decodeIfPresent(String.self, forKey: .teamId)
        opp = try c.decodeIfPresent(String.self, forKey: .opp)
        home = try c.decodeIfPresent(Bool.self, forKey: .home)
        wl = try c.decodeIfPresent(String.self, forKey: .wl)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        func gi(_ k: CodingKeys) throws -> Int? { try c.decodeIfPresent(Int.self, forKey: k) }
        pts = try gi(.pts); reb = try gi(.reb); ast = try gi(.ast); stl = try gi(.stl)
        blk = try gi(.blk); tov = try gi(.tov); oreb = try gi(.oreb); dreb = try gi(.dreb)
        pf = try gi(.pf); fgm = try gi(.fgm); fga = try gi(.fga); fg3m = try gi(.fg3m)
        fg3a = try gi(.fg3a); ftm = try gi(.ftm); fta = try gi(.fta)
        plusMinus = try gi(.plusMinus)
        missed = try c.decodeIfPresent(Bool.self, forKey: .missed) ?? false
    }
}
