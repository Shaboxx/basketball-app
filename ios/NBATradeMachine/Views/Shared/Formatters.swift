import Foundation

enum Money {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func display(_ amount: Int?) -> String {
        guard let amount, amount > 0 else { return "—" }
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
