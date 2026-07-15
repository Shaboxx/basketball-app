import Foundation

/// The `playerShots/_league` doc: the league per-cell FG% baseline + the mean-PPS anchor.
/// Rides the repurposed FirestoreReading meta slot. `baseline` is 624 row-major doubles; a
/// JSON `null` cell decodes to `Double.nan` (masked). `isValid` is the geometry + value-range
/// comparability contract (section 8.2) — a false result => reject the doc (bundle fallback ->
/// else heat unavailable).
nonisolated struct LeagueField: Codable, Equatable {
    let schemaVersion: Int
    let season: String
    let geometry: Geometry
    let baseline: [Double]        // 624; NaN where JSON null
    let leagueMeanPPS: Double
    let leagueMinMass: Double

    struct Geometry: Codable, Equatable {
        let cols, rows, spacing, xMin, yMin, sigma, cutoff: Int
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, season, geometry, baseline, leagueMeanPPS, leagueMinMass
    }

    init(schemaVersion: Int, season: String, geometry: Geometry, baseline: [Double],
         leagueMeanPPS: Double, leagueMinMass: Double) {
        self.schemaVersion = schemaVersion; self.season = season; self.geometry = geometry
        self.baseline = baseline; self.leagueMeanPPS = leagueMeanPPS; self.leagueMinMass = leagueMinMass
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        season = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
        geometry = try c.decodeIfPresent(Geometry.self, forKey: .geometry)
            ?? Geometry(cols: 0, rows: 0, spacing: 0, xMin: 0, yMin: 0, sigma: 0, cutoff: 0)
        // baseline: decode each element as Double? (JSON null -> nil) and map nil -> NaN.
        let raw = try c.decodeIfPresent([Double?].self, forKey: .baseline) ?? []
        baseline = raw.map { $0 ?? Double.nan }
        leagueMeanPPS = try c.decodeIfPresent(Double.self, forKey: .leagueMeanPPS) ?? 0
        leagueMinMass = try c.decodeIfPresent(Double.self, forKey: .leagueMinMass) ?? 0
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(season, forKey: .season)
        try c.encode(geometry, forKey: .geometry)
        // NaN -> JSON null on the way out (round-trips the masked cells).
        try c.encode(baseline.map { $0.isNaN ? Double?.none : $0 }, forKey: .baseline)
        try c.encode(leagueMeanPPS, forKey: .leagueMeanPPS)
        try c.encode(leagueMinMass, forKey: .leagueMinMass)
    }

    /// True iff the doc matches the pinned grid/kernel + length AND the value ranges (section 8.2).
    var isValid: Bool {
        let geometryOK =
            schemaVersion == 1 && baseline.count == 26 * 24 &&
            geometry.cols == 26 && geometry.rows == 24 && geometry.spacing == 20 &&
            geometry.xMin == -250 && geometry.yMin == -48 && geometry.sigma == 30 && geometry.cutoff == 90
        let ppsOK = leagueMeanPPS.isFinite && leagueMeanPPS >= 0.8 && leagueMeanPPS <= 1.4
        let baselineOK = baseline.allSatisfy { $0.isNaN || ($0.isFinite && $0 >= 0.0 && $0 <= 1.0) }
        return geometryOK && ppsOK && baselineOK
    }
}
