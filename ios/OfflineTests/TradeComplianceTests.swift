import XCTest
@testable import BasketballOffline

final class TradeComplianceTests: XCTestCase {

    // MARK: helpers
    func ctx(
        team: String = "LAL",
        pre: Int = 150_000_000,
        post: Int = 150_000_000,
        tier: LeagueRules.CapTier = .overCap,
        incoming: [ContractLite] = [],
        outgoing: [ContractLite] = [],
        cash: Int = 0,
        roster: Int = 15,
        offseason: Bool = false,
        firstRoundYears: Set<Int> = [2026, 2027, 2028],
        preFirstRoundYears: Set<Int>? = nil,   // defaults to firstRoundYears (no trade-created gap)
        horizon: ClosedRange<Int> = 2026...2032,
        hardCapLimit: Int? = nil,
        acquiringViaSignAndTrade: Bool = false,
        signAndTradePriorTeamIds: [String] = [],
        tradeTeamIds: Set<String> = [],
        signedExceptions: [ExceptionType] = [],
        signAndTradeAcquiredYears: [Int] = [],
        conveyedFirstRoundYears: [Int] = [],
        conveyedPickYears: [Int] = [],
        currentDraftYear: Int = 2026,
        cashReceived: Int = 0,
        twoWayCount: Int? = nil,
        scenarioDate: Date? = nil,
        standingTPEs: [Int] = []
    ) -> TeamContext {
        TeamContext(
            teamId: team, teamName: team, preTradeSalary: pre, postTradeSalary: post,
            postTradeTier: tier, incoming: incoming, outgoing: outgoing, cashSent: cash,
            postTradeRosterCount: roster, isOffseason: offseason,
            ownedFirstRoundYears: firstRoundYears,
            preTradeOwnedFirstRoundYears: preFirstRoundYears ?? firstRoundYears,
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
            cashReceived: cashReceived,
            twoWayCount: twoWayCount,
            scenarioDate: scenarioDate,
            standingTPEs: standingTPEs
        )
    }

    func contract(_ salary: Int, max: Int? = 50_000_000) -> ContractLite {
        ContractLite(playerId: "p\(salary)", name: "P\(salary)", salaryY1: salary,
                     standardMax: max, nextContractMax: max)
    }

    // MARK: roster
    func test_roster_over_max_blocks() {
        let issues = TradeCompliance.rosterIssues(ctx(roster: 16))
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.severity, .block)
        XCTAssertEqual(issues.first?.category, .roster)
    }

    func test_roster_15_and_14_ok() {
        XCTAssertTrue(TradeCompliance.rosterIssues(ctx(roster: 15)).isEmpty)
        XCTAssertTrue(TradeCompliance.rosterIssues(ctx(roster: 14)).isEmpty)
    }

    func test_roster_under_min_warns() {
        let issues = TradeCompliance.rosterIssues(ctx(roster: 13))
        XCTAssertEqual(issues.first?.severity, .warn)
    }

    // MARK: salary matching
    func test_match_overCap_expandedTPE_allows_200pct_small() {
        // outgoing 5M -> formula1 = min(2*5M+250k, 5M+7.936M)=10.25M ; formula2=6.5M -> allowed 10.25M
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overCap, outgoing: 5_000_000, capRoom: 0), 10_250_000)
    }

    func test_match_overCap_expandedTPE_caps_at_breakpoint() {
        // outgoing 20M -> formula1 = min(40.25M, 27.936M)=27.936M ; formula2=25.25M -> allowed 27.936M
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overTax, outgoing: 20_000_000, capRoom: 0), 27_936_000)
    }

    func test_match_firstApron_is_100pct() {
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overFirstApron, outgoing: 20_000_000, capRoom: 0), 20_000_000)
    }

    func test_match_secondApron_is_100pct() {
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .overSecondApron, outgoing: 20_000_000, capRoom: 0), 20_000_000)
    }

    func test_match_underCap_room_plus_buffer_no_outgoing() {
        // Pure cap-room absorption (taking back salary, sending nothing): room + $250k.
        XCTAssertEqual(TradeCompliance.allowedIncoming(tier: .underCap, outgoing: 0, capRoom: 12_000_000), 12_250_000)
    }

    func test_match_underCap_includes_outgoing() {
        // The outgoing salaries also free cap space: room + outgoing + $250k.
        // room 5M + outgoing 20M + 250k = 25.25M (was 5.25M before the fix).
        XCTAssertEqual(
            TradeCompliance.allowedIncoming(tier: .underCap, outgoing: 20_000_000, capRoom: 5_000_000),
            25_250_000)
    }

    func test_match_underCap_evenMoney_atCap_not_blocked() {
        // Regression: a team essentially AT the cap (room 0) swapping near-identical
        // salaries must NOT be blocked — the outgoing fully offsets the incoming.
        let t = ctx(pre: TradeCompliance.salaryCapFallback, tier: .underCap,
                    incoming: [contract(20_000_000)], outgoing: [contract(20_100_000)])
        XCTAssertTrue(TradeCompliance.salaryMatchIssues(t).isEmpty)
    }

    func test_match_block_when_incoming_exceeds_allowed() {
        let t = ctx(tier: .overFirstApron, incoming: [contract(25_000_000)], outgoing: [contract(20_000_000)])
        let issues = TradeCompliance.salaryMatchIssues(t)
        XCTAssertEqual(issues.first?.severity, .block)
        XCTAssertEqual(issues.first?.category, .salaryMatch)
    }

    func test_match_ok_within_allowed() {
        let t = ctx(tier: .overCap, incoming: [contract(9_000_000)], outgoing: [contract(5_000_000)])
        XCTAssertTrue(TradeCompliance.salaryMatchIssues(t).isEmpty)
    }

    // MARK: B1 — TradeAnalyzer.validate is structural-only (no flat 125% matching cap)
    func test_tradeAnalyzer_validate_allows_expandedTPE_matching() {
        // $5M out -> $9M in failed the old flat 125%+$250k ($6.5M) cap; validate() now
        // only enforces send-and-receive, leaving matching to the tier-aware engine.
        let flows = [TradeAnalyzer.TeamFlow(teamId: "A", teamName: "A", outgoing: 5_000_000, incoming: 9_000_000),
                     TradeAnalyzer.TeamFlow(teamId: "B", teamName: "B", outgoing: 9_000_000, incoming: 5_000_000)]
        XCTAssertTrue(TradeAnalyzer.validate(flows: flows).isValid)
    }

    func test_tradeAnalyzer_validate_allows_one_way_flow_but_requires_involvement() {
        // SG1: a one-way salary flow (receive-only or send-only) is legal — matching is
        // enforced by the tier-aware engine. A team moving nothing is still invalid.
        let receiveOnly = [TradeAnalyzer.TeamFlow(teamId: "A", teamName: "A", outgoing: 0, incoming: 9_000_000)]
        XCTAssertTrue(TradeAnalyzer.validate(flows: receiveOnly).isValid)
        let sendOnly = [TradeAnalyzer.TeamFlow(teamId: "A", teamName: "A", outgoing: 9_000_000, incoming: 0)]
        XCTAssertTrue(TradeAnalyzer.validate(flows: sendOnly).isValid)
        let nothing = [TradeAnalyzer.TeamFlow(teamId: "A", teamName: "A", outgoing: 0, incoming: 0)]
        XCTAssertFalse(TradeAnalyzer.validate(flows: nothing).isValid)
    }

    // MARK: apron + cash
    func test_secondApron_blocks_aggregation() {
        // sends 2 players, takes back one larger than its biggest outgoing -> aggregation
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(25_000_000)],
                    outgoing: [contract(15_000_000), contract(8_000_000)])
        let issues = TradeCompliance.apronIssues(t)
        XCTAssertTrue(issues.contains { $0.severity == .block && $0.category == .apron && $0.message.contains("aggregat") })
    }

    func test_secondApron_no_aggregation_when_single_incoming_fits() {
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(14_000_000)],
                    outgoing: [contract(15_000_000), contract(8_000_000)])
        XCTAssertFalse(TradeCompliance.apronIssues(t).contains { $0.message.contains("aggregat") })
    }

    func test_secondApron_blocks_cash_sent() {
        let t = ctx(tier: .overSecondApron, cash: 1)
        XCTAssertTrue(TradeCompliance.apronIssues(t).contains { $0.severity == .block && $0.message.contains("cash") })
    }

    func test_secondApron_warns_frozen_pick() {
        let t = ctx(tier: .overSecondApron)
        XCTAssertTrue(TradeCompliance.apronIssues(t).contains { $0.severity == .warn && $0.message.contains("frozen") })
    }

    func test_firstApron_no_aggregation_block() {
        let t = ctx(tier: .overFirstApron,
                    incoming: [contract(25_000_000)],
                    outgoing: [contract(15_000_000), contract(8_000_000)])
        XCTAssertFalse(TradeCompliance.apronIssues(t).contains { $0.message.contains("aggregat") })
    }

    func test_cash_over_limit_blocks() {
        // B5: the per-team annual cash limit is a hard cap -> .block, not .warn.
        let t = ctx(tier: .overCap, cash: 9_000_000)
        XCTAssertTrue(TradeCompliance.cashIssues(t).contains { $0.severity == .block && $0.category == .cash })
    }

    // MARK: Stepien
    func test_stepien_two_consecutive_gaps_block_when_trade_creates_them() {
        // Pre-trade owned 2026-2029; post owns only 2026 & 2029 -> the trade conveys
        // 2027 & 2028, CREATING a consecutive gap.
        let t = ctx(firstRoundYears: [2026, 2029],
                    preFirstRoundYears: [2026, 2027, 2028, 2029], horizon: 2026...2032)
        let issues = TradeCompliance.stepienIssues(t)
        XCTAssertEqual(issues.first?.severity, .block)
        XCTAssertEqual(issues.first?.category, .stepien)
    }

    func test_stepien_preexisting_gap_not_blamed_on_trade() {
        // B4: the gap already existed pre-trade (curated-data incompleteness); a trade
        // that doesn't change owned picks must NOT block.
        let t = ctx(firstRoundYears: [2026, 2029],
                    preFirstRoundYears: [2026, 2029], horizon: 2026...2032)
        XCTAssertTrue(TradeCompliance.stepienIssues(t).isEmpty)
    }

    func test_stepien_alternating_ok() {
        let t = ctx(firstRoundYears: [2026, 2028, 2030, 2032], horizon: 2026...2032)
        XCTAssertTrue(TradeCompliance.stepienIssues(t).isEmpty)
    }

    func test_stepien_single_gap_ok() {
        let t = ctx(firstRoundYears: [2026, 2027, 2029, 2030, 2031, 2032], horizon: 2026...2032)
        XCTAssertTrue(TradeCompliance.stepienIssues(t).isEmpty)  // only 2028 missing
    }

    // MARK: max salary
    func test_maxSalary_warns_when_incoming_over_max() {
        let t = ctx(incoming: [contract(40_000_000, max: 35_000_000)])
        XCTAssertTrue(TradeCompliance.maxSalaryIssues(t).contains { $0.severity == .warn && $0.category == .maxSalary })
    }

    func test_maxSalary_ok_within_max() {
        let t = ctx(incoming: [contract(30_000_000, max: 35_000_000)])
        XCTAssertTrue(TradeCompliance.maxSalaryIssues(t).isEmpty)
    }

    // MARK: evaluate
    func test_evaluate_collects_block_and_warn() {
        let team = ctx(tier: .overSecondApron, incoming: [contract(25_000_000)],
                       outgoing: [contract(15_000_000), contract(8_000_000)],
                       cash: 1, roster: 16)
        let issues = TradeCompliance.evaluate(teams: [team])
        let hasRosterBlock = issues.contains { $0.severity == .block && $0.category == .roster }
        let hasApronBlock = issues.contains { $0.severity == .block && $0.category == .apron }
        let hasApronWarn = issues.contains { $0.severity == .warn && $0.category == .apron }
        XCTAssertTrue(hasRosterBlock)
        XCTAssertTrue(hasApronBlock)
        XCTAssertTrue(hasApronWarn)
    }

    // MARK: hard cap (M2)
    func test_hardCap_block_when_over_limit() {
        let t = ctx(post: 200_000_000, hardCapLimit: 195_945_000)
        let issues = TradeCompliance.hardCapIssues(t)
        XCTAssertEqual(issues.first?.severity, .block)
        XCTAssertEqual(issues.first?.category, .hardCap)
    }

    func test_hardCap_ok_when_under_limit() {
        let t = ctx(post: 190_000_000, hardCapLimit: 195_945_000)
        XCTAssertTrue(TradeCompliance.hardCapIssues(t).isEmpty)
    }

    func test_hardCap_ok_when_not_hardCapped() {
        let t = ctx(post: 220_000_000, hardCapLimit: nil)
        XCTAssertTrue(TradeCompliance.hardCapIssues(t).isEmpty)
    }

    // MARK: exception hard-cap mapping (M2 / B2)
    func test_exception_hardCap_apron_mapping() {
        // B2: taxpayer MLE hard-caps at the SECOND apron; the others at the first.
        XCTAssertEqual(ExceptionType.taxpayerMLE.hardCapApron, .second)
        XCTAssertEqual(ExceptionType.nonTaxpayerMLE.hardCapApron, .first)
        XCTAssertEqual(ExceptionType.biAnnual.hardCapApron, .first)
        XCTAssertEqual(ExceptionType.signAndTrade.hardCapApron, .first)
        XCTAssertNil(ExceptionType.capSpace.hardCapApron)
        XCTAssertNil(ExceptionType.minimum.hardCapApron)
        XCTAssertNil(ExceptionType.birdRights.hardCapApron)
        XCTAssertNil(ExceptionType.roomMLE.hardCapApron)
    }

    // MARK: B3 — second-apron aggregation bin-packing
    func test_secondApron_aggregation_bin_packing_counterexample() {
        // out [20M,10M], in [15M,14M]: total matches (29<=30) and no single incoming
        // exceeds 20M, yet 14M can't be placed without aggregating 20M+10M -> block.
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(15_000_000), contract(14_000_000)],
                    outgoing: [contract(20_000_000), contract(10_000_000)])
        XCTAssertTrue(TradeCompliance.apronIssues(t).contains { $0.severity == .block && $0.message.contains("aggregat") })
    }

    func test_secondApron_two_small_into_one_outgoing_is_legal() {
        // out [20M,10M], in [9M,9M]: both fit into the 20M slot -> no aggregation.
        let t = ctx(tier: .overSecondApron,
                    incoming: [contract(9_000_000), contract(9_000_000)],
                    outgoing: [contract(20_000_000), contract(10_000_000)])
        XCTAssertFalse(TradeCompliance.apronIssues(t).contains { $0.message.contains("aggregat") })
    }

    func test_canMatchWithoutAggregation_unit() {
        XCTAssertFalse(TradeCompliance.canMatchWithoutAggregation(incoming: [15, 14], outgoing: [20, 10]))
        XCTAssertTrue(TradeCompliance.canMatchWithoutAggregation(incoming: [9, 9], outgoing: [20, 10]))
        XCTAssertTrue(TradeCompliance.canMatchWithoutAggregation(incoming: [], outgoing: [20]))
        XCTAssertTrue(TradeCompliance.canMatchWithoutAggregation(incoming: [10, 8], outgoing: [10, 8]))
    }

    // MARK: M2 — offseason roster max
    func test_offseason_roster_16_to_21_warns_not_blocks() {
        let t = ctx(roster: 18, offseason: true)
        let issues = TradeCompliance.rosterIssues(t)
        XCTAssertEqual(issues.first?.severity, .warn)
        XCTAssertEqual(issues.first?.category, .roster)
    }

    func test_offseason_roster_over_21_blocks() {
        let t = ctx(roster: 22, offseason: true)
        XCTAssertEqual(TradeCompliance.rosterIssues(t).first?.severity, .block)
    }

    func test_inseason_roster_16_blocks() {
        let t = ctx(roster: 16, offseason: false)
        XCTAssertEqual(TradeCompliance.rosterIssues(t).first?.severity, .block)
    }

    // MARK: M1 — sign-and-trade prior-team participant
    func test_signAndTrade_prior_team_must_participate() {
        // S&T player's prior team "BKN" is NOT among the trade's teams -> block.
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true,
                    signAndTradePriorTeamIds: ["BKN"], tradeTeamIds: ["LAL", "GSW"])
        XCTAssertTrue(TradeCompliance.signAndTradeIssues(t).contains {
            $0.severity == .block && $0.message.contains("prior team") })
    }

    func test_signAndTrade_prior_team_present_ok() {
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true,
                    signAndTradePriorTeamIds: ["GSW"], tradeTeamIds: ["LAL", "GSW"])
        XCTAssertFalse(TradeCompliance.signAndTradeIssues(t).contains {
            $0.severity == .block && $0.message.contains("prior team") })
    }

    // MARK: sign-and-trade (M3)
    func test_sat_block_when_over_first_apron() {
        let t = ctx(tier: .overFirstApron, acquiringViaSignAndTrade: true)
        let issues = TradeCompliance.signAndTradeIssues(t)
        XCTAssertTrue(issues.contains { $0.severity == .block && $0.category == .signAndTrade })
        XCTAssertTrue(issues.contains { $0.severity == .warn && $0.category == .signAndTrade })
    }

    func test_sat_block_when_over_second_apron() {
        let t = ctx(tier: .overSecondApron, acquiringViaSignAndTrade: true)
        XCTAssertTrue(TradeCompliance.signAndTradeIssues(t).contains { $0.severity == .block })
    }

    func test_sat_warn_only_below_apron() {
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true)
        let issues = TradeCompliance.signAndTradeIssues(t)
        XCTAssertFalse(issues.contains { $0.severity == .block })
        XCTAssertTrue(issues.contains { $0.severity == .warn })
    }

    func test_sat_none_when_not_acquiring() {
        let t = ctx(tier: .overSecondApron, acquiringViaSignAndTrade: false)
        XCTAssertTrue(TradeCompliance.signAndTradeIssues(t).isEmpty)
    }

    // MARK: SG1 — one-way absorption (salary matching of the receiving side)
    func test_sg1_underCap_oneWay_receive_within_room_ok() {
        let t = ctx(pre: TradeCompliance.salaryCapFallback - 30_000_000, tier: .underCap,
                    incoming: [contract(20_000_000)], outgoing: [])
        XCTAssertTrue(TradeCompliance.salaryMatchIssues(t).isEmpty)
    }
    func test_sg1_overCap_oneWay_receive_blocks() {
        let t = ctx(tier: .overCap, incoming: [contract(20_000_000)], outgoing: [])
        XCTAssertEqual(TradeCompliance.salaryMatchIssues(t).first?.severity, .block)
    }
    func test_sg1_no_incoming_is_noop() {
        let t = ctx(tier: .overCap, incoming: [], outgoing: [contract(20_000_000)])
        XCTAssertTrue(TradeCompliance.salaryMatchIssues(t).isEmpty)
    }

    // SG2 (exception eligibility) is enforced by the hard cap — see hardCap tests
    // (using an ineligible exception over its apron trips hardCapIssues).

    // MARK: SG3/SG4 — sign-and-trade term + MLE conflict
    func test_sg3_sat_term_outside_3_to_4_blocks() {
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true, signAndTradeAcquiredYears: [2])
        XCTAssertTrue(TradeCompliance.signAndTradeIssues(t).contains {
            $0.severity == .block && $0.message.contains("3 to 4 years") })
    }
    func test_sg3_sat_term_3_years_ok() {
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true, signAndTradeAcquiredYears: [3])
        XCTAssertFalse(TradeCompliance.signAndTradeIssues(t).contains { $0.message.contains("3 to 4 years") })
    }
    func test_sg4_sat_conflicts_with_NTMLE() {
        let t = ctx(tier: .overCap, acquiringViaSignAndTrade: true,
                    signedExceptions: [.signAndTrade, .nonTaxpayerMLE])
        XCTAssertTrue(TradeCompliance.signAndTradeIssues(t).contains {
            $0.severity == .block && $0.message.contains("can't be combined") })
    }

    // MARK: SG5/SG6 — draft-pick trade limits
    func test_sg6_pick_beyond_7_years_blocks() {
        let t = ctx(conveyedPickYears: [2034], currentDraftYear: 2026)
        XCTAssertTrue(TradeCompliance.draftPickIssues(t).contains {
            $0.severity == .block && $0.message.contains("7 drafts") })
    }
    func test_sg6_pick_within_7_years_ok() {
        let t = ctx(conveyedPickYears: [2033], currentDraftYear: 2026)
        XCTAssertTrue(TradeCompliance.draftPickIssues(t).isEmpty)
    }
    func test_sg5_secondApron_frozen_first_round_pick_blocks() {
        let t = ctx(tier: .overSecondApron, conveyedFirstRoundYears: [2033],
                    conveyedPickYears: [2033], currentDraftYear: 2026)
        XCTAssertTrue(TradeCompliance.draftPickIssues(t).contains { $0.message.contains("frozen") })
    }

    // MARK: SG7 — received-cash limit
    func test_sg7_cash_received_over_limit_blocks() {
        let t = ctx(cashReceived: 9_000_000)
        XCTAssertTrue(TradeCompliance.cashIssues(t).contains {
            $0.severity == .block && $0.message.contains("receiving") })
    }

    // MARK: SG8-SG12 — scaffolded (fire on synthetic data, inert without it)
    func contractDated(_ salary: Int, acquired: Date? = nil, min: Bool? = nil) -> ContractLite {
        ContractLite(playerId: "p\(salary)\(acquired?.timeIntervalSince1970 ?? 0)", name: "P\(salary)",
                     salaryY1: salary, standardMax: 50_000_000, nextContractMax: 50_000_000,
                     acquiredDate: acquired, isMinimumContract: min)
    }
    private var asOf: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func test_sg8_twoWay_over_max_blocks() {
        XCTAssertEqual(TradeCompliance.twoWayIssues(ctx(twoWayCount: 4)).first?.severity, .block)
    }
    func test_sg8_twoWay_inert_without_data() {
        XCTAssertTrue(TradeCompliance.twoWayIssues(ctx(twoWayCount: nil)).isEmpty)
    }
    func test_sg9_aggregation_newly_acquired_blocks_with_data() {
        let recent = asOf.addingTimeInterval(-30 * 86_400), old = asOf.addingTimeInterval(-200 * 86_400)
        let t = ctx(tier: .overCap,
                    outgoing: [contractDated(10_000_000, acquired: recent), contractDated(8_000_000, acquired: old)],
                    scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).contains {
            $0.severity == .block && $0.message.contains("acquired") })
    }
    func test_sg9_aggregation_inert_without_scenarioDate() {
        let recent = asOf.addingTimeInterval(-30 * 86_400)
        let t = ctx(tier: .overCap,
                    outgoing: [contractDated(10_000_000, acquired: recent), contractDated(8_000_000, acquired: recent)],
                    scenarioDate: nil)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).isEmpty)
    }
    func test_sg10_multiple_minimums_blocks_with_data() {
        let t = ctx(tier: .overCap,
                    outgoing: [contractDated(2_000_000, min: true), contractDated(2_000_000, min: true),
                               contractDated(10_000_000, min: false)],
                    scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.aggregationTimingIssues(t).contains { $0.message.contains("minimum") })
    }
    func test_sg11_tpe_secondApron_oneWay_blocks_with_data() {
        let t = ctx(tier: .overSecondApron, incoming: [contract(5_000_000)], outgoing: [],
                    standingTPEs: [7_000_000])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).contains { $0.severity == .block })
    }
    func test_sg11_tpe_inert_without_standingTPEs() {
        let t = ctx(tier: .overSecondApron, incoming: [contract(5_000_000)], outgoing: [], standingTPEs: [])
        XCTAssertTrue(TradeCompliance.tpeIssues(t).isEmpty)
    }
    func test_sg12_waitingPeriod_recent_acquisition_warns_with_data() {
        let recent = asOf.addingTimeInterval(-30 * 86_400)
        let t = ctx(tier: .overCap, outgoing: [contractDated(10_000_000, acquired: recent)], scenarioDate: asOf)
        XCTAssertTrue(TradeCompliance.waitingPeriodIssues(t).contains {
            $0.severity == .warn && $0.category == .waitingPeriod })
    }
    func test_sg12_waitingPeriod_inert_without_dates() {
        let t = ctx(tier: .overCap, outgoing: [contract(10_000_000)], scenarioDate: nil)
        XCTAssertTrue(TradeCompliance.waitingPeriodIssues(t).isEmpty)
    }
}
