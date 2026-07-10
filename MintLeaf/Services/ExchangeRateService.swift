import Foundation

final class ExchangeRateService: Sendable {
    static let shared = ExchangeRateService()

    private static let cacheKey = "cachedExchangeRates"
    private static let fetchedAtKey = "exchangeRatesFetchedAt"

    // Fallback rates relative to USD (1 USD = X units of currency), used until the
    // first successful fetch and for currencies the ECB feed doesn't cover.
    private let fallbackRates: [String: Decimal] = [
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

    /// Live rates cached from the last successful fetch, overriding the fallback table.
    private var cachedRates: [String: Decimal] {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: Double] else { return [:] }
        return dict.mapValues { Decimal($0) }
    }

    private func rate(for code: String) -> Decimal? {
        cachedRates[code] ?? fallbackRates[code]
    }

    /// Convert an amount from one currency to another
    func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal {
        guard source != target else { return amount }
        let sourceRate = rate(for: source) ?? 1.0
        let targetRate = rate(for: target) ?? 1.0
        // Convert to USD first, then to target
        let inUSD = amount / sourceRate
        return inUSD * targetRate
    }

    /// Fetches live ECB rates (via frankfurter.dev, free/no key) and caches them.
    /// Throttled to once per day; silently keeps the previous cache or the
    /// fallback table when offline. Safe to call on every launch.
    func refresh() async {
        if let last = UserDefaults.standard.object(forKey: Self.fetchedAtKey) as? Date,
           Calendar.current.isDateInToday(last) { return }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD") else { return }

        struct Response: Decodable { let rates: [String: Double] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard !decoded.rates.isEmpty else { return }
            var merged = (UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: Double]) ?? [:]
            for (code, value) in decoded.rates where value > 0 { merged[code] = value }
            merged["USD"] = 1.0
            UserDefaults.standard.set(merged, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date(), forKey: Self.fetchedAtKey)
        } catch {
            // Offline or API down — stale cache/fallback rates still apply.
        }
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
