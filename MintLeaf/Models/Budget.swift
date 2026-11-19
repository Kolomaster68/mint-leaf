import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var name: String
    var period: BudgetPeriod
    var startDate: Date
    var createdAt: Date
    /// Unspent money carries into the next period (and overspend comes out of it).
    var rollover: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BudgetItem.budget)
    var items: [BudgetItem]

    var totalBudgeted: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var totalSpent: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.spent }
    }

    /// Budgeted plus anything rolled over — what can actually be spent this period.
    var totalAvailable: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.available }
    }

    /// The budget period containing `date`. Budgets recur, so this rolls forward from
    /// `startDate` in whole periods — previously `spent` only ever looked at the first
    /// period, so a monthly budget froze on its first month's numbers for good.
    /// Every boundary is computed from the anchor, so a budget started on the 31st
    /// doesn't drift to the 28th after February.
    func currentPeriod(at date: Date = Date()) -> (start: Date, end: Date) {
        let p = period(at: date)
        return (p.start, p.end)
    }

    /// Same as `currentPeriod`, plus how many whole periods have passed since the start.
    func period(at date: Date = Date()) -> (index: Int, start: Date, end: Date) {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: startDate)
        func boundary(_ n: Int) -> Date {
            let shifted: Date?
            switch period {
            case .weekly: shifted = cal.date(byAdding: .day, value: 7 * n, to: anchor)
            case .biweekly: shifted = cal.date(byAdding: .day, value: 14 * n, to: anchor)
            case .monthly: shifted = cal.date(byAdding: .month, value: n, to: anchor)
            case .quarterly: shifted = cal.date(byAdding: .month, value: 3 * n, to: anchor)
            case .yearly: shifted = cal.date(byAdding: .year, value: n, to: anchor)
            }
            return shifted ?? anchor
        }
        guard date >= anchor else { return (0, anchor, boundary(1)) } // not started yet

        let elapsed = cal.dateComponents([.day, .month, .year], from: anchor, to: date)
        var n: Int
        switch period {
        case .weekly: n = (cal.dateComponents([.day], from: anchor, to: date).day ?? 0) / 7
        case .biweekly: n = (cal.dateComponents([.day], from: anchor, to: date).day ?? 0) / 14
        case .monthly: n = (elapsed.year ?? 0) * 12 + (elapsed.month ?? 0)
        case .quarterly: n = ((elapsed.year ?? 0) * 12 + (elapsed.month ?? 0)) / 3
        case .yearly: n = elapsed.year ?? 0
        }
        // The estimate can be one out around clamped month-ends; settle it exactly.
        while boundary(n + 1) <= date { n += 1 }
        while n > 0 && boundary(n) > date { n -= 1 }
        return (n, boundary(n), boundary(n + 1))
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
}

@Model
final class BudgetItem {
    var id: UUID
    var amount: Decimal
    var category: Category?
    var budget: Budget?

    var spent: Decimal {
        guard let category, let budget else { return 0 }
        let window = budget.currentPeriod()
        return category.transactions
            .filter { $0.date >= window.start && $0.date < window.end && $0.isExpense }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    /// With rollover on: every earlier period's budget minus everything spent in them.
    /// Cumulative, so a bad month keeps counting against you until it's paid back.
    var carriedOver: Decimal {
        guard let category, let budget, budget.rollover else { return 0 }
        let now = budget.period()
        guard now.index > 0 else { return 0 }
        let start = Calendar.current.startOfDay(for: budget.startDate)
        let spentBefore = category.transactions
            .filter { $0.date >= start && $0.date < now.start && $0.isExpense }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
        return amount * Decimal(now.index) - spentBefore
    }

    var available: Decimal { amount + carriedOver }
    var remaining: Decimal { available - spent }
    var progress: Double {
        guard available > 0 else { return spent > 0 ? 1 : 0 }
        return Double(truncating: (spent / available) as NSDecimalNumber)
    }

    init(amount: Decimal, category: Category? = nil, budget: Budget? = nil) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.budget = budget
    }
}
