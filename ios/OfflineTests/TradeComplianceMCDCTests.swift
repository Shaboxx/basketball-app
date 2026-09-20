import XCTest
@testable import BasketballOffline

/// MC/DC (Modified Condition/Decision Coverage) suite for the COMPOUND decisions in
/// `TradeCompliance`. Each test is one row of an MC/DC truth table; the full set of
/// rows + the independence pairs are recorded in `docs/testing/mcdc-manifest.json`
/// and verified by `scripts/mcdc/mcdc_gate.py`. Test names here are referenced by
/// that manifest — renaming one without updating the manifest fails the gate.
///
/// Covered decisions (see the manifest for the per-condition independence pairs):
///   swift.tpeIssues.guard        A && B && C && D   (4-condition, 5 rows)
///   swift.apronIssues.aggregation A && B
///   swift.draftPick.frozen        A && B
///   swift.signAndTrade.apron      A || B  (coupled enum tier)
///   swift.signAndTrade.term       A || B  (coupled integer years)
///   swift.twoWay.count            A && B  (short-circuit / masking)
///   swift.maxSalary.exceeds       A && B  (short-circuit / masking)
final class TradeComplianceMCDCTests: XCTestCase {

    // MARK: fixtures (mirror TradeComplianceTests.ctx so each decision's inputs are explicit)
    func ctx(
        tier: LeagueRules.CapTier = .overCap,
        incoming: [ContractLite] = [],
        outgoing: [ContractLite] = [],
        cash: Int = 0,
        postTradeSalary: Int = 150_000_000,
        hardCapLimit: Int? = nil,
        acquiringViaSignAndTrade: Bool = false,
        signAndTradePriorTeamIds: [String] = [],
        tradeTeamIds: Set<String> = [],
        signedExceptions: [ExceptionType] = [],
        signAndTradeAcquiredYears: [Int] = [],
        conveyedFirstRoundYears: [Int] = [],
        conveyedPickYears: [Int] = [],
        currentDraftYear: Int = 2026,
        twoWayCount: Int? = nil,
        standingTPEs: [Int] = [],
        ownedFirstRoundYears: Set<Int> = [2026, 2027, 2028],
        preOwnedFirstRoundYears: Set<Int> = [2026, 2027, 2028],
        horizon: ClosedRange<Int> = 2026...2032,
        scenarioDate: Date? = nil
    ) -> TeamContext {
        TeamContext(
            teamId: "LAL", teamName: "LAL", preTradeSalary: 150_000_000, postTradeSalary: postTradeSalary,
            postTradeTier: tier, incoming: incoming, outgoing: outgoing, cashSent: cash,
            postTradeRosterCount: 15, isOffseason: false,
            ownedFirstRoundYears: ownedFirstRoundYears,
            preTradeOwnedFirstRoundYears: preOwnedFirstRoundYears,
            draftYearHorizon: horizon,
            hardCapLimit: hardCapLimit,
            acquiringViaSignAndTrade: acquiringViaSignAndTrade,
            signAndTradePriorTeamIds: signAndTradePriorTeamIds,
            tradeTeamIds: tradeTeamIds,
            signedExceptions: signedExceptions,
            signAndTradeAcquiredYears: signAndTradeAcquiredYears,
            conveyedFirstRoundYears: conveyedFirstRoundYears,
            conveyedPickYears: conveyedPickYears,
            currentDraftYear: currentDraftYear,
            cashReceived: 0,
            twoWayCount: twoWayCount,
            scenarioDate: scenarioDate,
            standingTPEs: standingTPEs)
    }

    func contract(_ salary: Int, max: Int? = 50_000_000) -> ContractLite {
        ContractLite(playerId: "p\(salary)", name: "P\(salary)", salaryY1: salary,
                     standardMax: max, nextContractMax: max)
    }

    /// A dated contract for the aggregation-timing / waiting-period windows.
    func dated(_ salary: Int, acquired: Date?) -> ContractLite {
        ContractLite(playerId: "p\(salary)", name: "P\(salary)", salaryY1: salary,
                     standardMax: 50_000_000, nextContractMax: 50_000_000, acquiredDate: acquired)
    }

    // Fixed "as-of" plus recent (<60d) / old (>60d) acquisition dates.
    let asOf = Date(timeIntervalSince1970: 1_700_000_000)
    var recentAcq: Date { asOf.addingTimeInterval(-30 * 86_400) }   // 30 days ago -> < 60
    var oldAcq: Date { asOf.addingTimeInterval(-90 * 86_400) }      // 90 days ago -> >= 60

    private func hasBlock(_ issues: [ComplianceIssue]) -> Bool {
        issues.contains { $0.severity == .block }
    }
    private func hasWarn(_ issues: [ComplianceIssue]) -> Bool {
        issues.contains { $0.severity == .warn }
    }

    // MARK: swift.tpeIssues.guard — A && B && C && D
    //  A=secondApron  B=hasStandingTPE  C=noOutgoing  D=hasIncoming
    func testTpe_allTrue_blocks() {                                    // TTTT -> block
        let t = ctx(tier: .overSecondApron, incoming: [contract(10_000_000)],
                    outgoing: [], standingTPEs: [5_000_000])
        XCTAssertTrue(hasBlock(TradeCompliance.tpeIssues(t)))
    }
    func testTpe_notSecondApron_noBlock() {                           // FTTT (A independence)
        let t = ctx(tier: .overFirstApron, incoming: [contract(10_000_000)],
                    outgoing: [], standingTPEs: [5_000_000])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).isEmpty)
    }
    func testTpe_noStandingTpe_noBlock() {                            // TFTT (B independence)
        let t = ctx(tier: .overSecondApron, incoming: [contract(10_000_000)],
                    outgoing: [], standingTPEs: [])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).isEmpty)
    }
    func testTpe_hasOutgoing_noBlock() {                              // TTFT (C independence)
        let t = ctx(tier: .overSecondApron, incoming: [contract(10_000_000)],
                    outgoing: [contract(9_000_000)], standingTPEs: [5_000_000])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).isEmpty)
    }
    func testTpe_noIncoming_noBlock() {                              // TTTF (D independence)
        let t = ctx(tier: .overSecondApron, incoming: [],
                    outgoing: [], standingTPEs: [5_000_000])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).isEmpty)
    }

    // MARK: swift.apronIssues.aggregation — A && B  (context: second apron; cash=0 isolates the block)
    //  A=outgoing.count>=2  B=!canMatchWithoutAggregation
    func testApronAgg_twoOutgoing_cantMatch_blocks() {               // TT -> block
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(9_000_000)],
                    outgoing: [contract(5_000_000), contract(5_000_000)])
        XCTAssertTrue(hasBlock(TradeCompliance.apronIssues(t)))
    }
    func testApronAgg_singleOutgoing_noBlock() {                     // FT (A independence)
        // A=F (one outgoing) but B genuinely TRUE (incoming $11M can't fit the single $10M
        // outgoing) — so B is held fixed T for A's independence pair, faithful to fixture.
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(11_000_000)],
                    outgoing: [contract(10_000_000)])
        XCTAssertFalse(hasBlock(TradeCompliance.apronIssues(t)))
    }
    func testApronAgg_twoOutgoing_fits_noBlock() {                   // TF (B independence)
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(4_000_000), contract(4_000_000)],
                    outgoing: [contract(5_000_000), contract(5_000_000)])
        XCTAssertFalse(hasBlock(TradeCompliance.apronIssues(t)))
    }

    // MARK: swift.draftPick.frozen — A && B
    //  A=secondApron  B=conveys frozen (currentDraftYear+7 = 2033) first-rounder
    func testDraftFrozen_secondApron_conveysMaxYear_blocks() {       // TT -> block
        let t = ctx(tier: .overSecondApron, conveyedFirstRoundYears: [2033], conveyedPickYears: [])
        XCTAssertTrue(hasBlock(TradeCompliance.draftPickIssues(t)))
    }
    func testDraftFrozen_notSecondApron_noBlock() {                  // FT (A independence)
        let t = ctx(tier: .overFirstApron, conveyedFirstRoundYears: [2033], conveyedPickYears: [])
        XCTAssertFalse(hasBlock(TradeCompliance.draftPickIssues(t)))
    }
    func testDraftFrozen_noMaxYearPick_noBlock() {                   // TF (B independence)
        let t = ctx(tier: .overSecondApron, conveyedFirstRoundYears: [2030], conveyedPickYears: [])
        XCTAssertFalse(hasBlock(TradeCompliance.draftPickIssues(t)))
    }

    // MARK: swift.signAndTrade.apron — A || B  (A=firstApron, B=secondApron; coupled tier)
    //  isolate the apron block: no prior-team/term/exception issues.
    func testSat_firstApron_blocks() {                              // TF -> block (A independence vs FF)
        let t = ctx(tier: .overFirstApron, acquiringViaSignAndTrade: true)
        XCTAssertTrue(hasBlock(TradeCompliance.signAndTradeIssues(t)))
    }
    func testSat_secondApron_blocks() {                             // FT -> block (B independence vs FF)
        let t = ctx(tier: .overSecondApron, acquiringViaSignAndTrade: true)
        XCTAssertTrue(hasBlock(TradeCompliance.signAndTradeIssues(t)))
    }
    func testSat_belowApron_noApronBlock() {                        // FF -> no block (only advisory warn)
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true)
        let issues = TradeCompliance.signAndTradeIssues(t)
        XCTAssertFalse(hasBlock(issues))
        XCTAssertTrue(hasWarn(issues))   // the standing S&T advisory still fires
    }

    // MARK: swift.signAndTrade.term — A || B  (A=years<3, B=years>4; coupled integer)
    //  tier below apron so the apron block can't confound the term block.
    func testSatTerm_twoYears_blocks() {                            // TF -> block (A independence)
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true, signAndTradeAcquiredYears: [2])
        XCTAssertTrue(hasBlock(TradeCompliance.signAndTradeIssues(t)))
    }
    func testSatTerm_fiveYears_blocks() {                           // FT -> block (B independence)
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true, signAndTradeAcquiredYears: [5])
        XCTAssertTrue(hasBlock(TradeCompliance.signAndTradeIssues(t)))
    }
    func testSatTerm_threeYears_ok() {                              // FF -> no block
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true, signAndTradeAcquiredYears: [3])
        XCTAssertFalse(hasBlock(TradeCompliance.signAndTradeIssues(t)))
    }

    // MARK: swift.twoWay.count — A && B  (A=count!=nil, B=count>3; short-circuit masking)
    func testTwoWay_overMax_blocks() {                              // TT -> block
        XCTAssertTrue(hasBlock(TradeCompliance.twoWayIssues(ctx(twoWayCount: 4))))
    }
    func testTwoWay_atMax_noBlock() {                               // TF (B independence)
        XCTAssertTrue(TradeCompliance.twoWayIssues(ctx(twoWayCount: 3)).isEmpty)
    }
    func testTwoWay_nilCount_noBlock() {                            // F- (A independence; B masked)
        XCTAssertTrue(TradeCompliance.twoWayIssues(ctx(twoWayCount: nil)).isEmpty)
    }

    // MARK: swift.maxSalary.exceeds — A && B  (A=cap known, B=salary>cap; short-circuit masking)
    func testMaxSalary_overCap_warns() {                           // TT -> warn
        let t = ctx(incoming: [contract(60_000_000, max: 50_000_000)])
        XCTAssertTrue(hasWarn(TradeCompliance.maxSalaryIssues(t)))
    }
    func testMaxSalary_withinCap_ok() {                            // TF (B independence)
        let t = ctx(incoming: [contract(40_000_000, max: 50_000_000)])
        XCTAssertTrue(TradeCompliance.maxSalaryIssues(t).isEmpty)
    }
    func testMaxSalary_noCap_noWarn() {                           // F- (A independence; B masked)
        let noCap = ContractLite(playerId: "x", name: "X", salaryY1: 60_000_000,
                                 standardMax: nil, nextContractMax: nil)
        XCTAssertTrue(TradeCompliance.maxSalaryIssues(ctx(incoming: [noCap])).isEmpty)
    }

    // MARK: swift.aggTiming.guard — A && B  (A=scenarioDate!=nil, B=outgoing.count>=2)
    //  A recent-acquisition player is held in `outgoing`, so guard-pass => SG9 block,
    //  guard-fail => no block — making the guard's outcome directly observable.
    func testAggTiming_dateAndTwoPlus_recentPlayer_blocks() {       // TT -> block
        let t = ctx(outgoing: [dated(9_000_000, acquired: recentAcq), dated(9_000_000, acquired: oldAcq)],
                    scenarioDate: asOf)
        XCTAssertTrue(hasBlock(TradeCompliance.aggregationTimingIssues(t)))
    }
    func testAggTiming_oneOutgoing_noBlock() {                      // TF (B independence)
        let t = ctx(outgoing: [dated(9_000_000, acquired: recentAcq)], scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).isEmpty)
    }
    func testAggTiming_noScenarioDate_noBlock() {                   // F- (A independence; B masked)
        let t = ctx(outgoing: [dated(9_000_000, acquired: recentAcq), dated(9_000_000, acquired: oldAcq)],
                    scenarioDate: nil)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).isEmpty)
    }

    // MARK: swift.aggTiming.recentAcquisition — A && B  (A=acquiredDate!=nil, B=daysBetween<60)
    //  Guard held open (scenarioDate set, 2 outgoing) so this per-player decision is isolated.
    func testAggRecent_recentDate_blocks() {                        // TT -> block
        let t = ctx(outgoing: [dated(9_000_000, acquired: recentAcq), dated(8_000_000, acquired: oldAcq)],
                    scenarioDate: asOf)
        XCTAssertTrue(hasBlock(TradeCompliance.aggregationTimingIssues(t)))
    }
    func testAggRecent_oldDate_noBlock() {                          // TF (B independence)
        let t = ctx(outgoing: [dated(9_000_000, acquired: oldAcq), dated(8_000_000, acquired: oldAcq)],
                    scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).isEmpty)
    }
    func testAggRecent_noDate_noBlock() {                           // F- (A independence; B masked)
        let t = ctx(outgoing: [dated(9_000_000, acquired: nil), dated(8_000_000, acquired: nil)],
                    scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).isEmpty)
    }

    // MARK: swift.waitingPeriod.recentAcquisition — A && B  (A=acquiredDate!=nil, B=daysBetween<60)
    //  Emits a WARN (not a block). scenarioDate set so the guard is open.
    func testWait_recentDate_warns() {                             // TT -> warn
        let t = ctx(outgoing: [dated(9_000_000, acquired: recentAcq)], scenarioDate: asOf)
        XCTAssertTrue(hasWarn(TradeCompliance.waitingPeriodIssues(t)))
    }
    func testWait_oldDate_noWarn() {                               // TF (B independence)
        let t = ctx(outgoing: [dated(9_000_000, acquired: oldAcq)], scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.waitingPeriodIssues(t).isEmpty)
    }
    func testWait_noDate_noWarn() {                                // F- (A independence; B masked)
        let t = ctx(outgoing: [dated(9_000_000, acquired: nil)], scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.waitingPeriodIssues(t).isEmpty)
    }

    // MARK: swift.stepien.consecutiveGap — A && B  (A=!owned(y), B=!owned(y+1))
    //  Tight horizon 2030...2031 so only y=2030 is evaluated; pre owns both years (no
    //  pre-existing gap) so the block reflects a TRADE-CREATED consecutive gap at 2030.
    func testStepien_bothYearsMissing_blocks() {                   // TT -> block
        let t = ctx(ownedFirstRoundYears: [], preOwnedFirstRoundYears: [2030, 2031], horizon: 2030...2031)
        XCTAssertTrue(hasBlock(TradeCompliance.stepienIssues(t)))
    }
    func testStepien_firstYearOwned_noBlock() {                    // FT (A independence): 2030 present
        let t = ctx(ownedFirstRoundYears: [2030], preOwnedFirstRoundYears: [2030, 2031], horizon: 2030...2031)
        XCTAssertTrue(TradeCompliance.stepienIssues(t).isEmpty)
    }
    func testStepien_secondYearOwned_noBlock() {                   // TF (B independence): 2031 present
        let t = ctx(ownedFirstRoundYears: [2031], preOwnedFirstRoundYears: [2030, 2031], horizon: 2030...2031)
        XCTAssertTrue(TradeCompliance.stepienIssues(t).isEmpty)
    }

    // MARK: swift.hardCap.guard — A && B  (A=hardCapLimit!=nil, B=postTradeSalary>limit)
    //  Independence vectors, complementary to the existing TradeComplianceTests hardCap cases.
    func testHardCapM_overLimit_blocks() {                         // TT -> block
        XCTAssertTrue(hasBlock(TradeCompliance.hardCapIssues(ctx(postTradeSalary: 150_000_000, hardCapLimit: 140_000_000))))
    }
    func testHardCapM_underLimit_noBlock() {                       // TF (B independence)
        XCTAssertTrue(TradeCompliance.hardCapIssues(ctx(postTradeSalary: 150_000_000, hardCapLimit: 160_000_000)).isEmpty)
    }
    func testHardCapM_notCapped_noBlock() {                        // F- (A independence; B masked)
        XCTAssertTrue(TradeCompliance.hardCapIssues(ctx(postTradeSalary: 150_000_000, hardCapLimit: nil)).isEmpty)
    }
}
