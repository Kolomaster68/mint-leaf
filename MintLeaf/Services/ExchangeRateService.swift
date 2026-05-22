import Foundation

final class ExchangeRateService: Sendable {
    static let shared = ExchangeRateService()

    // Rates relative to USD (1 USD = X units of currency)
    // Approximate rates — good enough for personal budgeting
    private let rates: [String: Decimal] = [
        "USD": 1.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "CAD": 1.36,
        "AUD": 1.53,
        "NZD": 1.67,
        "JPY": 154.5,
        "CNY": 7.24,
        "INR": 83.5,
        "CHF": 0.88,
        "SEK": 10.45,
        "NOK": 10.6,
        "DKK": 6.87,
        "PLN": 3.98,
        "CZK": 23.2,
        "HUF": 362.0,
        "BRL": 4.97,
        "MXN": 17.15,
        "ARS": 850.0,
        "ZAR": 18.6,
        "KRW": 1320.0,
        "SGD": 1.34,
        "HKD": 7.82,
        "TWD": 31.5,
        "THB": 35.8,
        "MYR": 4.72,
        "PHP": 56.2,
        "IDR": 15700.0,
        "TRY": 32.4,
        "RUB": 91.5,
        "SAR": 3.75,
        "AED": 3.67,
        "ILS": 3.65,
        "EGP": 30.9,
        "NGN": 1550.0,
        "KES": 153.0,
        "CLP": 940.0,
        "COP": 3950.0,
        "PEN": 3.72,
    ]

    /// Convert an amount from one currency to another
    func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal {
        guard source != target else { return amount }
        let sourceRate = rates[source] ?? 1.0
        let targetRate = rates[target] ?? 1.0
        // Convert to USD first, then to target
        let inUSD = amount / sourceRate
        return inUSD * targetRate
    }

    /// Get the user's preferred currency
    var preferredCurrency: String {
        UserDefaults.standard.string(forKey: "defaultCurrency") ?? "USD"
    }

    /// Format an amount converted to the user's preferred currency
    func formatConverted(_ amount: Decimal, from source: String) -> String {
        let converted = convert(amount, from: source, to: preferredCurrency)
        return CurrencyFormatter.shared.format(converted)
    }
}
