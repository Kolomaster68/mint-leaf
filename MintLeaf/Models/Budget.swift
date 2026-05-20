import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var name: String
    var period: BudgetPeriod
    var startDate: Date
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BudgetItem.budget)
    var items: [BudgetItem]

    var totalBudgeted: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var totalSpent: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.spent }
    }

    init(name: String, period: BudgetPeriod = .monthly, startDate: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.period = period
        self.startDate = startDate
        self.createdAt = Date()
        self.items = []
    }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 90
        case .yearly: return 365
        }
    }
}

@Model
final class BudgetItem {
    var id: UUID
    var amount: Decimal
    var category: Category?
    var budget: Budget?

    var spent: Decimal {
        guard let category, let budget else { return 0 }
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: budget.period.days, to: budget.startDate) ?? Date()
        return category.transactions
            .filter { $0.date >= budget.startDate && $0.date < endDate && $0.isExpense }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    var remaining: Decimal { amount - spent }
    var progress: Double { amount == 0 ? 0 : Double(truncating: (spent / amount) as NSDecimalNumber) }

    init(amount: Decimal, category: Category? = nil, budget: Budget? = nil) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.budget = budget
    }
}
