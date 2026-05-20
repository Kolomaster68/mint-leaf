import Foundation
import SwiftData

@Model
final class CategoryRule {
    var id: UUID
    var pattern: String
    var matchType: RuleMatchType
    var sortOrder: Int
    var isEnabled: Bool
    var createdAt: Date

    @Relationship
    var category: Category?

    init(
        pattern: String,
        matchType: RuleMatchType = .contains,
        category: Category? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.pattern = pattern
        self.matchType = matchType
        self.category = category
        self.sortOrder = sortOrder
        self.isEnabled = true
        self.createdAt = Date()
    }

    func matches(_ text: String) -> Bool {
        guard isEnabled else { return false }
        let lowered = text.lowercased()
        let pat = pattern.lowercased()
        switch matchType {
        case .contains:
            return lowered.contains(pat)
        case .startsWith:
            return lowered.hasPrefix(pat)
        case .endsWith:
            return lowered.hasSuffix(pat)
        case .exact:
            return lowered == pat
        case .regex:
            return (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))
                .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil } ?? false
        }
    }
}

enum RuleMatchType: String, Codable, CaseIterable, Identifiable {
    case contains = "Contains"
    case startsWith = "Starts With"
    case endsWith = "Ends With"
    case exact = "Exact Match"
    case regex = "Regex"

    var id: String { rawValue }
}
