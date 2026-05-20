import Foundation
import SwiftData

struct CategorySuggestion {
    let category: Category
    let confidence: Double
    let reason: String
}

final class AutoCategorizer {
    // Built-in keyword → category name mappings (matched against the seeded defaults)
    private static let keywordMap: [(keywords: [String], categoryName: String)] = [
        // Food & Dining
        (["restaurant", "cafe", "coffee", "costa", "starbucks", "pret", "nandos", "nando's",
          "mcdonald", "mcdonalds", "burger king", "kfc", "subway", "pizza", "dominos",
          "greggs", "wetherspoon", "wagamama", "five guys", "gourmet", "bistro", "diner",
          "chippy", "fish bar", "kebab", "sushi", "thai", "indian", "chinese", "pub ",
          "bar ", "inn ", "tavern", "fellow", "coborn"], "Food & Dining"),

        // Groceries
        (["tesco", "sainsbury", "asda", "aldi", "lidl", "morrisons", "waitrose", "m&s food",
          "co-op", "coop", "iceland", "ocado", "grocery", "supermarket", "whole foods",
          "trader joe", "kroger", "walmart supercenter"], "Groceries"),

        // Transportation
        (["uber", "lyft", "bolt ", "taxi", "cab ", "trainpal", "trainline", "national rail",
          "tfl", "oyster", "transport for", "bus ", "railway", "eurostar", "avanti",
          "parking", "ncp ", "justpark", "ringgo"], "Transportation"),

        // Gas & Fuel
        (["shell ", "bp ", "esso", "texaco", "total ", "jet ", "petrol", "fuel", "gas station",
          "exxon", "chevron", "costco fuel"], "Gas & Fuel"),

        // Housing
        (["rent ", "mortgage", "letting", "estate agent", "rightmove", "zoopla"], "Housing"),

        // Utilities
        (["electric", "gas bill", "water bill", "british gas", "edf", "eon", "octopus energy",
          "bulb", "sse ", "thames water", "severn trent", "council tax", "openreach",
          "virgin media", "bt ", "sky ", "utility"], "Utilities"),

        // Insurance
        (["insurance", "aviva", "direct line", "admiral", "axa ", "zurich", "prudential",
          "legal & general"], "Insurance"),

        // Healthcare
        (["pharmacy", "chemist", "boots ", "superdrug", "doctor", "dentist", "optician",
          "specsavers", "hospital", "medical", "health"], "Healthcare"),

        // Entertainment
        (["netflix", "disney+", "disney plus", "prime video", "spotify", "apple music",
          "youtube", "cinema", "odeon", "cineworld", "vue ", "theatre", "theater",
          "concert", "ticketmaster", "eventbrite", "playstation", "xbox", "steam ",
          "nintendo", "nvidia", "game"], "Entertainment"),

        // Shopping
        (["amazon", "ebay", "etsy", "asos", "argos", "john lewis", "debenhams",
          "currys", "ikea", "primark", "next ", "h&m", "zara", "very.co",
          "target", "best buy"], "Shopping"),

        // Clothing
        (["clothing", "clothes", "fashion", "shoes", "trainers", "barber", "haircut",
          "hairdresser", "salon"], "Clothing"),

        // Education
        (["university", "college", "school", "tuition", "course", "udemy", "coursera",
          "skillshare", "textbook", "student"], "Education"),

        // Subscriptions
        (["subscription", "claude.ai", "openai", "chatgpt", "github", "icloud",
          "apple.com/bill", "google storage", "dropbox", "1password", "nordvpn",
          "expressvpn", "adobe", "microsoft 365", "office 365", "notion"], "Subscriptions"),

        // Travel
        (["hotel", "airbnb", "booking.com", "expedia", "hostel", "ryanair", "easyjet",
          "british airways", "flights", "airline", "airport"], "Travel"),

        // Gifts & Donations
        (["gift", "charity", "donate", "donation", "justgiving", "gofundme",
          "red cross", "oxfam", "cancer research"], "Gifts & Donations"),

        // Salary / Income
        (["salary", "wages", "payroll", "employer"], "Salary"),

        // Refunds
        (["refund", "reversal", "chargeback", "cashback"], "Refunds"),
    ]

    static func categorize(transaction: Transaction, categories: [Category], rules: [CategoryRule]) -> CategorySuggestion? {
        let title = transaction.title.lowercased()

        // Priority 1: user-defined rules
        for rule in rules.sorted(by: { $0.sortOrder < $1.sortOrder }) where rule.isEnabled {
            if rule.matches(transaction.title), let cat = rule.category {
                return CategorySuggestion(category: cat, confidence: 1.0, reason: "Matched rule: \(rule.pattern)")
            }
        }

        // Priority 2: built-in keyword matching
        for (keywords, categoryName) in keywordMap {
            for keyword in keywords {
                if title.contains(keyword.lowercased()) {
                    if let cat = categories.first(where: { $0.name == categoryName }) {
                        let confidence = keyword.count > 5 ? 0.9 : 0.7
                        return CategorySuggestion(category: cat, confidence: confidence, reason: "Matched keyword: \(keyword)")
                    }
                }
            }
        }

        // Priority 3: learn from past — find transactions with similar titles that have categories
        return nil
    }

    static func categorizeAll(transactions: [Transaction], categories: [Category], rules: [CategoryRule]) -> (categorized: Int, needsReview: Int) {
        var categorized = 0
        var needsReview = 0

        for transaction in transactions where transaction.category == nil {
            if let suggestion = categorize(transaction: transaction, categories: categories, rules: rules) {
                if suggestion.confidence >= 0.7 {
                    transaction.category = suggestion.category
                    categorized += 1
                } else {
                    needsReview += 1
                }
            } else {
                needsReview += 1
            }
        }

        return (categorized, needsReview)
    }
}
