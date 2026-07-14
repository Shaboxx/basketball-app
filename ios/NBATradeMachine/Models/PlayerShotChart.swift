import Foundation

/// A per-player `playerShots/{slug}` doc: the current-season offensive shot chart.
/// Forward-compatible (every field defaults) so a partial doc still decodes; keyed by
/// documentID (no slug field). Mirrors the FantasyValue decode pattern.
nonisolated struct PlayerShotChart: Codable, Equatable {
    let points: [ShotPoint]
    let zones: [String: ZoneTally]
    let meta: ShotMeta

    enum CodingKeys: String, CodingKey { case points, zones, meta }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([ShotPoint].self, forKey: .points) ?? []
        zones  = try c.decodeIfPresent([String: ZoneTally].self, forKey: .zones) ?? [:]
        meta   = try c.decodeIfPresent(ShotMeta.self, forKey: .meta) ?? .zero
    }
    init(points: [ShotPoint], zones: [String: ZoneTally], meta: ShotMeta) {
        self.points = points; self.zones = zones; self.meta = meta
    }

    struct ShotPoint: Codable, Equatable {
        let x, y, value: Int
        let made: Bool
        // CodingKey case names MUST match stored-property names (raw value = JSON key)
        // or Codable synthesis fails to compile.
        enum CodingKeys: String, CodingKey { case x, y, made = "m", value = "v" }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 0
            y = try c.decodeIfPresent(Int.self, forKey: .y) ?? 0
            made = (try c.decodeIfPresent(Int.self, forKey: .made) ?? 0) != 0
            value = try c.decodeIfPresent(Int.self, forKey: .value) ?? 2
        }
        init(x: Int, y: Int, made: Bool, value: Int) { self.x = x; self.y = y; self.made = made; self.value = value }
    }

    struct ZoneTally: Codable, Equatable {
        let fga, fgm: Int
        enum CodingKeys: String, CodingKey { case fga, fgm }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            fga = try c.decodeIfPresent(Int.self, forKey: .fga) ?? 0
            fgm = try c.decodeIfPresent(Int.self, forKey: .fgm) ?? 0
        }
        init(fga: Int, fgm: Int) { self.fga = fga; self.fgm = fgm }
        var fgPct: Double? { fga > 0 ? Double(fgm) / Double(fga) : nil }
    }

    struct ShotMeta: Codable, Equatable {
        let season: String
        let fga, fgm, droppedNoCoord: Int
        let asOf: String?
        enum CodingKeys: String, CodingKey { case season, fga, fgm, droppedNoCoord, asOf }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            season = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
            fga = try c.decodeIfPresent(Int.self, forKey: .fga) ?? 0
            fgm = try c.decodeIfPresent(Int.self, forKey: .fgm) ?? 0
            droppedNoCoord = try c.decodeIfPresent(Int.self, forKey: .droppedNoCoord) ?? 0
            asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
        }
        init(season: String, fga: Int, fgm: Int, droppedNoCoord: Int, asOf: String?) {
            self.season = season; self.fga = fga; self.fgm = fgm
            self.droppedNoCoord = droppedNoCoord; self.asOf = asOf
        }
        static let zero = ShotMeta(season: "", fga: 0, fgm: 0, droppedNoCoord: 0, asOf: nil)
    }
}
