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

extension Decimal {
    /// Parses an amount a person typed or a bank exported: "1,234.56", "£45", "(12.50)".
    /// `Decimal(string:)` stops at the first character it doesn't like, so "1,234.56"
    /// silently became 1 and "£45" became nil. This accepts the whole string or nothing.
    init?(userInput raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")") {   // accounting-style negative
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        s.removeAll { "£$€, \u{00A0}".contains($0) }
        if s.hasPrefix("+") { s.removeFirst() }
        guard s.range(of: #"^-?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil,
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = negative ? -value : value
    }
}
