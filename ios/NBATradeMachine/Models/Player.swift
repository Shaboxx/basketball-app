import Foundation

struct Player: Codable, Identifiable, Hashable {
    var docId: String? = nil
    let slug: String
    let name: String
    let teamId: String
    let position: String
    let heightInches: Int?
    let weightLbs: Int?
    let birthdate: String?       // ISO-8601 "YYYY-MM-DD"
    let primaryRole: String?
    let secondaryRole: String?
    let defensiveRole: String?
    let salaryY1: Int?
    let salaryY2: Int?
    let salaryY3: Int?
    let salaryY4: Int?

    // CBA Phase 1 fields (spec §4.3). All optional — old docs without CBA
    // data decode as nil.
    let yos: Int?
    let standardMax: Int?
    let minSalary: Int?
    let supermaxEligible: Bool?
    let nextContractMax: Int?
    let nextContractMaxBasis: String?
    let maxTierPct: Int?
    let higherMaxCriteriaMet: Bool?
    let supermaxPath: String?
    let contractFinalYearSalary: Int?
    let contractFinalYearSeasonEnd: Int?
    let cbaSeason: String?
    let cbaUpdatedAt: Date?

    // Phase 7 v2 latent value (theta-hat). Optional — old docs without latent
    // -value data decode as nil. Written by scripts/upload_latent_value.py.
    let latentValue: LatentValue?

    // Phase 7e composite valuation block. Optional — docs predating the
    // Phase 7e join decode as nil and downstream consumers fall back to
    // raw latentValue + contract math.
    let compZ: CompZValuation?

    // SP1 position eligibility (primary + adjacent-eligible positions).
    // Optional — docs without the upload decode as nil.
    let positionEligibility: PositionEligibility?

    // Phase 7 v2 impact block (written by scripts/upload_theta_v2.py).
    // Optional — docs without it decode as nil.
    let thetaV2: ThetaV2?

    // Team-relative trade value (written by scripts/upload_trade_value.py).
    // Optional — docs without it decode as nil.
    let tradeValue: TradeValue?

    // Lineup-labeling per-player feature record (written by
    // scripts/upload_lineup_features.py). Optional — docs without it decode as
    // nil and the lineup labeler abstains for that player.
    let lineupFeatures: LineupFeatures?

    // SP-A per-player marginal roster value (written by scripts/upload_roster_value.py).
    // Optional — docs without it decode as nil. (No `= nil` default: a `let` with a default is
    // excluded from the synthesized Decodable, which would force it to always be nil.)
    let rosterValue: RosterValue?

    // SP3 per-player relevance block (written by scripts/upload_relevance.py).
    // Optional — old docs without it decode as nil.
    // Field names match the Firestore map keys exactly.
    let relevance: Relevance?

    // θ-NN player-evaluation board value (written by the thetaboard pipeline).
    // Optional — docs without it decode as nil.
    let thetaBoard: ThetaBoardValue?

    /// Per-player relevance block used by the SP3 weighted team-OVR rollup.
    /// Written by scripts/upload_relevance.py; field names match the Firestore map keys.
    struct Relevance: Codable, Hashable {
        let mpgSeason: Double
        let mpgRecent: Double
        let gp: Int
        let usg: Double?
        let usgGames: Int
        let season: String
        let asOf: String?
    }

    // Explicit CodingKeys excludes the optional local `docId`; standalone
    // JSON decoding uses the stable slug when that identity is absent.
    // IMPORTANT: every stored property of `Player` except `docId`
    // MUST be listed below. A property missing from this enum will silently
    // decode as nil (or fail to encode) without any compile-time warning.
    enum CodingKeys: String, CodingKey {
        case slug, name, teamId, position
        case heightInches, weightLbs, birthdate
        case primaryRole, secondaryRole, defensiveRole
        case salaryY1, salaryY2, salaryY3, salaryY4
        case yos, standardMax, minSalary, supermaxEligible
        case nextContractMax, nextContractMaxBasis, maxTierPct, higherMaxCriteriaMet
        case supermaxPath, contractFinalYearSalary, contractFinalYearSeasonEnd
        case cbaSeason, cbaUpdatedAt
        case latentValue
        case compZ
        case positionEligibility
        case thetaV2
        case tradeValue
        case lineupFeatures
        case rosterValue
        case relevance
        case thetaBoard
    }

    var id: String { docId ?? slug }
    var currentSalary: Int { salaryY1 ?? 0 }

    var headshotPath: String { "headshots/\(slug).png" }

    var heightDisplay: String {
        guard let inches = heightInches else { return "—" }
        return "\(inches / 12)'\(inches % 12)\""
    }

    func salary(forSeasonOffset offset: Int) -> Int {
        switch offset {
        case 0: return salaryY1 ?? 0
        case 1: return salaryY2 ?? 0
        case 2: return salaryY3 ?? 0
        case 3: return salaryY4 ?? 0
        default: return 0
        }
    }

    func contractYearsRemaining(from offset: Int) -> Int {
        let years = [salaryY1, salaryY2, salaryY3, salaryY4]
        var count = 0
        for i in offset..<years.count {
            if (years[i] ?? 0) > 0 { count += 1 } else { break }
        }
        return count
    }
}

#if DEBUG
extension Player {
    /// Lightweight builder for unit/preview construction. Every field has a
    /// neutral default so tests can override only the fields they care about.
    /// `compZ`, `latentValue`, and all CBA Phase 1 fields default to nil so
    /// callers can exercise the "missing optional" branches explicitly.
    static func testFixture(
        slug: String = "test-player",
        name: String = "Test Player",
        teamId: String = "1610612737",
        position: String = "G",
        heightInches: Int? = 78,
        weightLbs: Int? = 210,
        birthdate: String? = nil,
        primaryRole: String? = nil,
        secondaryRole: String? = nil,
        defensiveRole: String? = nil,
        salaryY1: Int? = 10_000_000,
        salaryY2: Int? = nil,
        salaryY3: Int? = nil,
        salaryY4: Int? = nil,
        yos: Int? = nil,
        standardMax: Int? = nil,
        minSalary: Int? = nil,
        supermaxEligible: Bool? = nil,
        nextContractMax: Int? = nil,
        nextContractMaxBasis: String? = nil,
        maxTierPct: Int? = nil,
        higherMaxCriteriaMet: Bool? = nil,
        supermaxPath: String? = nil,
        contractFinalYearSalary: Int? = nil,
        contractFinalYearSeasonEnd: Int? = nil,
        cbaSeason: String? = nil,
        cbaUpdatedAt: Date? = nil,
        latentValue: LatentValue? = nil,
        compZ: CompZValuation? = nil,
        positionEligibility: PositionEligibility? = nil,
        thetaV2: ThetaV2? = nil,
        tradeValue: TradeValue? = nil,
        lineupFeatures: LineupFeatures? = nil,
        rosterValue: RosterValue? = nil,
        relevance: Relevance? = nil,
        thetaBoard: ThetaBoardValue? = nil
    ) -> Player {
        Player(
            slug: slug, name: name, teamId: teamId, position: position,
            heightInches: heightInches, weightLbs: weightLbs,
            birthdate: birthdate, primaryRole: primaryRole,
            secondaryRole: secondaryRole, defensiveRole: defensiveRole,
            salaryY1: salaryY1, salaryY2: salaryY2,
            salaryY3: salaryY3, salaryY4: salaryY4,
            yos: yos, standardMax: standardMax, minSalary: minSalary,
            supermaxEligible: supermaxEligible,
            nextContractMax: nextContractMax,
            nextContractMaxBasis: nextContractMaxBasis,
            maxTierPct: maxTierPct,
            higherMaxCriteriaMet: higherMaxCriteriaMet,
            supermaxPath: supermaxPath,
            contractFinalYearSalary: contractFinalYearSalary,
            contractFinalYearSeasonEnd: contractFinalYearSeasonEnd,
            cbaSeason: cbaSeason, cbaUpdatedAt: cbaUpdatedAt,
            latentValue: latentValue, compZ: compZ,
            positionEligibility: positionEligibility,
            thetaV2: thetaV2, tradeValue: tradeValue,
            lineupFeatures: lineupFeatures,
            rosterValue: rosterValue,
            relevance: relevance,
            thetaBoard: thetaBoard
        )
    }
}
#endif
