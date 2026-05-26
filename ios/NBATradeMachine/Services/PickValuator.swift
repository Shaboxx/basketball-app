import Foundation

enum PickValuator {

    private static let firstRoundValuesM: [Double] = [
        50.0, 42.0, 36.0, 31.0, 27.0, 24.0, 22.0, 20.0, 18.0, 17.0,
        16.0, 15.0, 14.0, 13.0, 12.0, 11.0, 10.0,  9.5,  9.0,  8.5,
         8.0,  7.5,  7.0,  6.5,  6.0,  5.5,  5.0,  4.5,  4.0,  3.5
    ]
    private static let firstRoundUnknown: Double = 12.0
    private static let secondRoundValueM: Double = 1.5
    private static let yearDiscountFactor: Double = 0.95

    static func value(for pick: Pick, currentYear: Int) -> Double {
        let base = baseValue(for: pick)
        let yearsAway = max(0, pick.year - currentYear)
        let yearDiscount = pow(yearDiscountFactor, Double(yearsAway))
        let selectionMultiplier = pick.selectionRule?.valueMultiplier ?? 1.0
        return base * yearDiscount * protectionMultiplier(for: pick.protection) * selectionMultiplier
    }

    private static func baseValue(for pick: Pick) -> Double {
        if pick.round == 2 { return secondRoundValueM }
        if let pos = pick.projectedPosition, (1...30).contains(pos) {
            return firstRoundValuesM[pos - 1]
        }
        return firstRoundUnknown
    }

    private static func protectionMultiplier(for protection: PickProtection) -> Double {
        switch protection {
        case .unprotected: return 1.0
        case .top4Protected: return 0.65
        case .top10Protected: return 0.45
        case .lotteryProtected: return 0.30
        case .other: return 0.55
        }
    }
}
