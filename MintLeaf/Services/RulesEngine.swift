import Foundation
import SwiftData

final class RulesEngine {
    static func applyRules(to transaction: Transaction, rules: [CategoryRule], aliases: [MerchantAlias]) {
        if transaction.category == nil {
            for rule in rules.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                if rule.matches(transaction.title) {
                    transaction.category = rule.category
                    break
                }
            }
        }

        for alias in aliases where alias.isEnabled {
            let rule = CategoryRule(pattern: alias.rawPattern, matchType: alias.matchType)
            if rule.matches(transaction.title) {
                transaction.title = alias.cleanName
                break
            }
        }
    }

    static func applyAll(transactions: [Transaction], rules: [CategoryRule], aliases: [MerchantAlias]) {
        for transaction in transactions {
            applyRules(to: transaction, rules: rules, aliases: aliases)
        }
    }

    static func learnRule(from transaction: Transaction, context: ModelContext) {
        guard let category = transaction.category else { return }
        let title = transaction.title.lowercased()
        let words = title.components(separatedBy: .whitespaces).filter { $0.count > 2 }
        guard let keyword = words.first else { return }

        let rule = CategoryRule(pattern: keyword, matchType: .contains, category: category)
        context.insert(rule)
    }
}
