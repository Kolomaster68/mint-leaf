import Foundation

final class MerchantNormalizer {
    static let defaultPatterns: [(pattern: String, clean: String)] = [
        ("AMZN MKTP", "Amazon"),
        ("AMAZON.CO", "Amazon"),
        ("AMAZON PRIME", "Amazon Prime"),
        ("PAYPAL \\*", ""),
        ("SQ \\*", ""),
        ("TST\\* ", ""),
        ("TESCO STORES?\\s*\\d*", "Tesco"),
        ("SAINSBURY", "Sainsbury's"),
        ("ASDA STORES?\\s*\\d*", "Asda"),
        ("MORRISONS\\s*\\d*", "Morrisons"),
        ("ALDI\\s*\\d*", "Aldi"),
        ("LIDL\\s*\\d*", "Lidl"),
        ("WAITROSE\\s*\\d*", "Waitrose"),
        ("UBER \\*EATS", "Uber Eats"),
        ("UBER   \\*TRIP", "Uber"),
        ("UBER BV", "Uber"),
        ("NETFLIX\\.COM", "Netflix"),
        ("SPOTIFY", "Spotify"),
        ("APPLE\\.COM/BILL", "Apple"),
        ("GOOGLE \\*", "Google"),
        ("MCDONALDS", "McDonald's"),
        ("STARBUCKS", "Starbucks"),
        ("PRET A MANGER", "Pret A Manger"),
        ("COSTA COFFEE", "Costa Coffee"),
        ("JUST EAT", "Just Eat"),
        ("DELIVEROO", "Deliveroo"),
    ]

    static func normalize(_ rawTitle: String) -> String {
        var result = rawTitle.trimmingCharacters(in: .whitespaces)

        for (pattern, clean) in defaultPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                if regex.firstMatch(in: result, range: range) != nil {
                    if clean.isEmpty {
                        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
                            .trimmingCharacters(in: .whitespaces)
                    } else {
                        return clean
                    }
                }
            }
        }

        result = stripTrailingReference(result)
        result = collapseWhitespace(result)
        return titleCase(result)
    }

    private static func stripTrailingReference(_ s: String) -> String {
        let pattern = "\\s+[A-Z0-9]{4,}\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func titleCase(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
