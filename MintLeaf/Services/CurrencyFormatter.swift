import Foundation

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()

    private static var defaultCurrency: String {
        UserDefaults.standard.string(forKey: "defaultCurrency") ?? "USD"
    }

    var symbol: String {
        let code = Self.defaultCurrency
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.currencySymbol ?? "$"
    }

    func format(_ amount: Decimal, currency: String? = nil) -> String {
        let code = currency ?? Self.defaultCurrency
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    func formatSigned(_ amount: Decimal, currency: String? = nil) -> String {
        let formatted = format(abs(amount), currency: currency)
        return amount < 0 ? "-\(formatted)" : "+\(formatted)"
    }
}
