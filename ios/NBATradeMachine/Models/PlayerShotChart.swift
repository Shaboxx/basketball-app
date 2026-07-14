import Foundation

/// A per-player `playerShots/{slug}` doc: the current-season offensive shot chart.
/// Forward-compatible (every field defaults) so a partial doc still decodes; keyed by
/// documentID (no slug field). Mirrors the FantasyValue decode pattern.
nonisolated struct PlayerShotChart: Codable, Equatable {
    let points: [ShotPoint]
    let zones: [String: ZoneTally]
    let meta: ShotMeta
    let profile: Profile?      // sub-project A: nil on older docs (pre-profile)

    enum CodingKeys: String, CodingKey { case points, zones, meta, profile }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([ShotPoint].self, forKey: .points) ?? []
        zones  = try c.decodeIfPresent([String: ZoneTally].self, forKey: .zones) ?? [:]
        meta   = try c.decodeIfPresent(ShotMeta.self, forKey: .meta) ?? .zero
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
    }
    init(points: [ShotPoint], zones: [String: ZoneTally], meta: ShotMeta, profile: Profile? = nil) {
        self.points = points; self.zones = zones; self.meta = meta; self.profile = profile
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

    /// The league-relative shot-profile block (schemaVersion 1). Forward/backward
    /// compatible: every field defaults, so a partial profile still decodes. Property
    /// names match the JSON contract keys exactly.
    struct Profile: Codable, Equatable {
        let schemaVersion: Int
        let bucket: String           // "PG/SG/SF/PF/C", coarse "G/F/C", or "none"
        let bucketMode: String       // "specific" | "coarse" | "none"
        let bucketN: Int
        let positionSource: String   // "players.json" | "eligibility.listedPrimary" | "none"
        let position: String?
        let role: String?
        let heightIn: Int?
        let wingspanIn: Int?
        let fga: Int
        let zones: [String: Zone]
        let mix: Mix
        let threePShare: Double
        let threePShareLeagueNorm: Double
        let signals: [String: Signal]

        enum CodingKeys: String, CodingKey {
            case schemaVersion, bucket, bucketMode, bucketN, positionSource, position, role
            case heightIn, wingspanIn, fga, zones, mix, threePShare, threePShareLeagueNorm, signals
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? "none"
            bucketMode = try c.decodeIfPresent(String.self, forKey: .bucketMode) ?? "none"
            bucketN = try c.decodeIfPresent(Int.self, forKey: .bucketN) ?? 0
            positionSource = try c.decodeIfPresent(String.self, forKey: .positionSource) ?? "none"
            position = try c.decodeIfPresent(String.self, forKey: .position)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            heightIn = try c.decodeIfPresent(Int.self, forKey: .heightIn)
            wingspanIn = try c.decodeIfPresent(Int.self, forKey: .wingspanIn)
            fga = try c.decodeIfPresent(Int.self, forKey: .fga) ?? 0
            zones = try c.decodeIfPresent([String: Zone].self, forKey: .zones) ?? [:]
            mix = try c.decodeIfPresent(Mix.self, forKey: .mix) ?? .zero
            threePShare = try c.decodeIfPresent(Double.self, forKey: .threePShare) ?? 0
            threePShareLeagueNorm = try c.decodeIfPresent(Double.self, forKey: .threePShareLeagueNorm) ?? 0
            signals = try c.decodeIfPresent([String: Signal].self, forKey: .signals) ?? [:]
        }

        struct Zone: Codable, Equatable {
            let share: Double
            let fgPct: Double?       // null on a zero-attempt zone
            let fga: Int
            enum CodingKeys: String, CodingKey { case share, fgPct, fga }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                share = try c.decodeIfPresent(Double.self, forKey: .share) ?? 0
                fgPct = try c.decodeIfPresent(Double.self, forKey: .fgPct)
                fga = try c.decodeIfPresent(Int.self, forKey: .fga) ?? 0
            }
        }

        struct Mix: Codable, Equatable {
            let rim: Double
            let rimLeagueNorm: Double
            let paintNonRim: Double
            let mid: Double
            let midLeagueNorm: Double
            let three: Double
            let threeLeagueNorm: Double
            enum CodingKeys: String, CodingKey {
                case rim, rimLeagueNorm, paintNonRim, mid, midLeagueNorm, three, threeLeagueNorm
            }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                rim = try c.decodeIfPresent(Double.self, forKey: .rim) ?? 0
                rimLeagueNorm = try c.decodeIfPresent(Double.self, forKey: .rimLeagueNorm) ?? 0
                paintNonRim = try c.decodeIfPresent(Double.self, forKey: .paintNonRim) ?? 0
                mid = try c.decodeIfPresent(Double.self, forKey: .mid) ?? 0
                midLeagueNorm = try c.decodeIfPresent(Double.self, forKey: .midLeagueNorm) ?? 0
                three = try c.decodeIfPresent(Double.self, forKey: .three) ?? 0
                threeLeagueNorm = try c.decodeIfPresent(Double.self, forKey: .threeLeagueNorm) ?? 0
            }
            init(rim: Double, rimLeagueNorm: Double, paintNonRim: Double, mid: Double,
                 midLeagueNorm: Double, three: Double, threeLeagueNorm: Double) {
                self.rim = rim; self.rimLeagueNorm = rimLeagueNorm; self.paintNonRim = paintNonRim
                self.mid = mid; self.midLeagueNorm = midLeagueNorm; self.three = three
                self.threeLeagueNorm = threeLeagueNorm
            }
            static let zero = Mix(rim: 0, rimLeagueNorm: 0, paintNonRim: 0, mid: 0,
                                  midLeagueNorm: 0, three: 0, threeLeagueNorm: 0)
        }

        struct Signal: Codable, Equatable {
            let value: Double
            let pct: Double
            let norm: Double
            enum CodingKeys: String, CodingKey { case value, pct, norm }
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
                pct = try c.decodeIfPresent(Double.self, forKey: .pct) ?? 0
                norm = try c.decodeIfPresent(Double.self, forKey: .norm) ?? 0
            }
            init(value: Double, pct: Double, norm: Double) {
                self.value = value; self.pct = pct; self.norm = norm
            }
        }
    }
}
