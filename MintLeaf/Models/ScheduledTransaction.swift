import Foundation
import SwiftData

@Model
final class ScheduledTransaction {
    var id: UUID
    var amount: Decimal
    var title: String
    var notes: String
    var frequency: RecurrenceFrequency
    var nextDate: Date
    var endDate: Date?
    var isActive: Bool
    var isSubscription: Bool
    var currency: String = "USD"

    @Relationship
    var account: Account?

    @Relationship
    var category: Category?

    @Relationship(deleteRule: .nullify)
    var generatedTransactions: [Transaction]

    var monthlyEquivalent: Decimal {
        let amt = abs(amount)
        switch frequency {
        case .daily: return amt * 30
        case .weekly: return amt * 4
        case .biweekly: return amt * 2
        case .monthly: return amt
        case .quarterly: return amt / 3
        case .yearly: return amt / 12
        }
    }

    var yearlyEquivalent: Decimal {
        monthlyEquivalent * 12
    }

    /// Amount converted to the user's preferred currency
    var convertedAmount: Decimal {
        ExchangeRateService.shared.convert(amount, from: currency, to: ExchangeRateService.shared.preferredCurrency)
    }

    /// Monthly equivalent in the user's preferred currency
    var convertedMonthlyEquivalent: Decimal {
        ExchangeRateService.shared.convert(monthlyEquivalent, from: currency, to: ExchangeRateService.shared.preferredCurrency)
    }

    init(
        amount: Decimal,
        title: String,
        frequency: RecurrenceFrequency = .monthly,
        nextDate: Date,
        account: Account? = nil,
        category: Category? = nil,
        isSubscription: Bool = false,
        currency: String? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.title = title
        self.notes = ""
        self.frequency = frequency
        self.nextDate = nextDate
        self.isActive = true
        self.isSubscription = isSubscription
        self.currency = currency ?? UserDefaults.standard.string(forKey: "defaultCurrency") ?? "USD"
        self.account = account
        self.category = category
        self.generatedTransactions = []
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"

    var id: String { rawValue }
}

enum SubscriptionDetector {
    private static let knownSubscriptions: Set<String> = [
        "netflix", "spotify", "hulu", "disney+", "disney plus", "apple tv",
        "apple music", "apple icloud", "icloud", "apple one", "amazon prime",
        "youtube", "youtube premium", "youtube tv", "hbo max", "hbo",
        "peacock", "paramount+", "paramount plus", "max", "crunchyroll",
        "adobe", "creative cloud", "microsoft 365", "office 365",
        "dropbox", "google one", "chatgpt", "openai", "claude",
        "nordvpn", "expressvpn", "surfshark", "1password", "lastpass",
        "dashlane", "notion", "evernote", "todoist", "grammarly",
        "audible", "kindle unlimited", "xbox game pass", "playstation plus",
        "ps plus", "nintendo online", "steam", "ea play",
        "peloton", "headspace", "calm", "noom", "strava",
        "doordash dashpass", "uber one", "walmart+", "walmart plus",
        "instacart", "costco", "sam's club", "bj's",
        "sirius", "siriusxm", "pandora", "tidal", "deezer",
        "github", "gitlab", "figma", "canva", "slack",
        "zoom", "duolingo", "masterclass", "skillshare", "coursera",
        "planet fitness", "anytime fitness", "la fitness", "ymca",
        "tiktok", "snapchat", "linkedin premium",
    ]

    static func looksLikeSubscription(title: String, amount: Decimal, frequency: RecurrenceFrequency) -> Bool {
        let lower = title.lowercased()
        if knownSubscriptions.contains(where: { lower.contains($0) }) {
            return true
        }
        let isRecurring = frequency == .monthly || frequency == .yearly || frequency == .quarterly
        let isSmallAmount = abs(amount) > 0 && abs(amount) <= 75
        return isRecurring && isSmallAmount && amount < 0
    }
}
