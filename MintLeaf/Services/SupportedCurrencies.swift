import Foundation

struct CurrencyInfo: Identifiable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }
}

enum SupportedCurrencies {
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "USD", name: "US Dollar", flag: "🇺🇸"),
        CurrencyInfo(code: "EUR", name: "Euro", flag: "🇪🇺"),
        CurrencyInfo(code: "GBP", name: "British Pound", flag: "🇬🇧"),
        CurrencyInfo(code: "CAD", name: "Canadian Dollar", flag: "🇨🇦"),
        CurrencyInfo(code: "AUD", name: "Australian Dollar", flag: "🇦🇺"),
        CurrencyInfo(code: "NZD", name: "New Zealand Dollar", flag: "🇳🇿"),
        CurrencyInfo(code: "JPY", name: "Japanese Yen", flag: "🇯🇵"),
        CurrencyInfo(code: "CNY", name: "Chinese Yuan", flag: "🇨🇳"),
        CurrencyInfo(code: "INR", name: "Indian Rupee", flag: "🇮🇳"),
        CurrencyInfo(code: "CHF", name: "Swiss Franc", flag: "🇨🇭"),
        CurrencyInfo(code: "SEK", name: "Swedish Krona", flag: "🇸🇪"),
        CurrencyInfo(code: "NOK", name: "Norwegian Krone", flag: "🇳🇴"),
        CurrencyInfo(code: "DKK", name: "Danish Krone", flag: "🇩🇰"),
        CurrencyInfo(code: "PLN", name: "Polish Zloty", flag: "🇵🇱"),
        CurrencyInfo(code: "CZK", name: "Czech Koruna", flag: "🇨🇿"),
        CurrencyInfo(code: "HUF", name: "Hungarian Forint", flag: "🇭🇺"),
        CurrencyInfo(code: "BRL", name: "Brazilian Real", flag: "🇧🇷"),
        CurrencyInfo(code: "MXN", name: "Mexican Peso", flag: "🇲🇽"),
        CurrencyInfo(code: "ARS", name: "Argentine Peso", flag: "🇦🇷"),
        CurrencyInfo(code: "ZAR", name: "South African Rand", flag: "🇿🇦"),
        CurrencyInfo(code: "KRW", name: "South Korean Won", flag: "🇰🇷"),
        CurrencyInfo(code: "SGD", name: "Singapore Dollar", flag: "🇸🇬"),
        CurrencyInfo(code: "HKD", name: "Hong Kong Dollar", flag: "🇭🇰"),
        CurrencyInfo(code: "TWD", name: "Taiwan Dollar", flag: "🇹🇼"),
        CurrencyInfo(code: "THB", name: "Thai Baht", flag: "🇹🇭"),
        CurrencyInfo(code: "MYR", name: "Malaysian Ringgit", flag: "🇲🇾"),
        CurrencyInfo(code: "PHP", name: "Philippine Peso", flag: "🇵🇭"),
        CurrencyInfo(code: "IDR", name: "Indonesian Rupiah", flag: "🇮🇩"),
        CurrencyInfo(code: "TRY", name: "Turkish Lira", flag: "🇹🇷"),
        CurrencyInfo(code: "RUB", name: "Russian Ruble", flag: "🇷🇺"),
        CurrencyInfo(code: "SAR", name: "Saudi Riyal", flag: "🇸🇦"),
        CurrencyInfo(code: "AED", name: "UAE Dirham", flag: "🇦🇪"),
        CurrencyInfo(code: "ILS", name: "Israeli Shekel", flag: "🇮🇱"),
        CurrencyInfo(code: "EGP", name: "Egyptian Pound", flag: "🇪🇬"),
        CurrencyInfo(code: "NGN", name: "Nigerian Naira", flag: "🇳🇬"),
        CurrencyInfo(code: "KES", name: "Kenyan Shilling", flag: "🇰🇪"),
        CurrencyInfo(code: "CLP", name: "Chilean Peso", flag: "🇨🇱"),
        CurrencyInfo(code: "COP", name: "Colombian Peso", flag: "🇨🇴"),
        CurrencyInfo(code: "PEN", name: "Peruvian Sol", flag: "🇵🇪"),
    ]

    static func info(for code: String) -> CurrencyInfo? {
        all.first { $0.code == code }
    }
}

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
