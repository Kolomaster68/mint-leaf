import Foundation

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f
    }()

    func format(_ amount: Decimal, currency: String = "USD") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    func formatSigned(_ amount: Decimal, currency: String = "USD") -> String {
        let formatted = format(abs(amount), currency: currency)
        return amount < 0 ? "-\(formatted)" : "+\(formatted)"
    }
}
