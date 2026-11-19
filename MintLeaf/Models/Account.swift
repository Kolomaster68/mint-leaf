import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var currency: String
    var initialBalance: Decimal
    var icon: String
    var colorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]

    var cachedBalance: Decimal

    // Credit card billing cycle (optional — only used for .creditCard accounts)
    /// Day of month the statement is cut (1–31). nil = not configured.
    var statementDay: Int?
    /// Number of days after the statement date that payment is due. Used when `paymentDueDay` is nil.
    var paymentDueOffsetDays: Int?
    /// Fixed day of month the payment is due (1–31). Takes precedence over `paymentDueOffsetDays` when set.
    var paymentDueDay: Int?
    /// For a credit card: the id of the account that pays this card's bill (e.g. a current account).
    var paymentSourceAccountID: UUID?
    /// For a current/savings account: arranged overdraft limit (a positive number). nil = no overdraft.
    var overdraftLimit: Decimal?
    /// Arranged overdraft interest rate as an annual EAR percentage (e.g. 39.9).
    var overdraftEAR: Decimal?
    /// Flat fee charged when the account goes beyond its arranged overdraft (e.g. a £20 monthly cap).
    var unarrangedOverdraftFee: Decimal?
    /// For a credit card: the annual purchase interest rate (APR) as a percentage (e.g. 22.9).
    var purchaseAPR: Decimal?

    var currentBalance: Decimal {
        cachedBalance
    }

    /// Balance converted to the user's display currency. Totals across accounts must
    /// use this — adding a USD balance to a GBP one as raw numbers is meaningless.
    var convertedBalance: Decimal {
        ExchangeRateService.shared.convert(currentBalance, from: currency,
                                           to: ExchangeRateService.shared.preferredCurrency)
    }

    func recalculateBalance() {
        cachedBalance = initialBalance + transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    func adjustBalance(by amount: Decimal) {
        cachedBalance += amount
    }

    // MARK: - Credit Card Billing Cycle

    /// Whether this account has a configured statement cycle.
    var hasBillingCycle: Bool {
        type == .creditCard && statementDay != nil
    }

    /// The most recent statement (closing) date on or before `reference`.
    func lastStatementDate(before reference: Date = Date()) -> Date? {
        guard let day = statementDay else { return nil }
        let cal = Calendar.current
        // Candidate in the reference month
        var comps = cal.dateComponents([.year, .month], from: reference)
        comps.day = clampDay(day, year: comps.year!, month: comps.month!)
        guard let thisMonth = cal.date(from: comps) else { return nil }
        if thisMonth <= cal.startOfDay(for: reference).addingTimeInterval(86400) {
            // statement this month has already passed (or is today)
            return thisMonth <= reference ? thisMonth : previousStatement(from: thisMonth)
        }
        return previousStatement(from: thisMonth)
    }

    /// Due date of the most recently cut statement — the one `statementBalance`
    /// describes. It can be in the past: an unpaid statement past this date is overdue.
    /// (This used to walk forward to the next *future* due date, which paired last
    /// month's balance with next month's deadline and made "overdue" unreachable.)
    func statementDueDate(asOf reference: Date = Date()) -> Date? {
        guard let statement = lastStatementDate(before: reference) else { return nil }
        return dueDate(forStatement: statement)
    }

    /// Computes the payment due date for a given statement date.
    private func dueDate(forStatement statement: Date) -> Date? {
        let cal = Calendar.current
        if let fixedDay = paymentDueDay {
            // First occurrence of the fixed day at least two weeks after the statement:
            // statement 15th / due 9th lands next month, statement 2nd / due 27th the
            // same month. ponytail: 14 days is a heuristic floor — no card gives less.
            guard let earliest = cal.date(byAdding: .day, value: 14, to: statement) else { return nil }
            var comps = cal.dateComponents([.year, .month], from: earliest)
            comps.day = clampDay(fixedDay, year: comps.year!, month: comps.month!)
            guard let candidate = cal.date(from: comps) else { return nil }
            if candidate >= earliest { return candidate }
            guard let nextMonth = cal.date(byAdding: .month, value: 1, to: candidate) else { return nil }
            var next = cal.dateComponents([.year, .month], from: nextMonth)
            next.day = clampDay(fixedDay, year: next.year!, month: next.month!)
            return cal.date(from: next)
        } else {
            let offset = paymentDueOffsetDays ?? 21
            return cal.date(byAdding: .day, value: offset, to: statement)
        }
    }

    /// First instant after the statement day — everything before it is billed.
    private func statementCloseEnd(_ statement: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: statement)) ?? statement
    }

    /// Statement balance: what the card owed at the moment the last statement was cut —
    /// i.e. minus the account balance at close, exactly what the paper statement prints.
    ///
    /// It is NOT the net of one cycle's transactions: the payment for the *previous*
    /// statement lands inside the cycle, so netting a single window cancels it against
    /// this cycle's spending and reports almost nothing owed.
    var statementBalance: Decimal {
        guard let lastStatement = lastStatementDate() else { return 0 }
        let closeEnd = statementCloseEnd(lastStatement)
        let balanceAtClose = initialBalance + transactions
            .filter { $0.date < closeEnd }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return -balanceAtClose
    }

    /// Unbilled balance: purchases since the last statement that roll into the next bill.
    /// Credits since then are payments (see `paymentsSinceStatement`), not negative spend.
    var unbilledBalance: Decimal {
        guard let lastStatement = lastStatementDate() else { return 0 }
        let closeEnd = statementCloseEnd(lastStatement)
        return -transactions
            .filter { $0.date >= closeEnd && $0.amount < 0 }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    // MARK: - Statement Payment Reconciliation

    /// Total payments (credits) applied to the card since the last statement closed.
    /// A payment is any positive-amount transaction posted after the statement date.
    var paymentsSinceStatement: Decimal {
        guard let lastStatement = lastStatementDate() else { return 0 }
        let closeEnd = statementCloseEnd(lastStatement)
        return transactions
            .filter { $0.date >= closeEnd && $0.amount > 0 }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Amount of the current statement still outstanding after payments (never negative).
    var statementRemaining: Decimal {
        max(0, statementBalance - paymentsSinceStatement)
    }

    /// True once payments since the statement closed cover (essentially) the statement balance.
    var statementSettled: Bool {
        let bal = statementBalance
        guard bal > 0 else { return true } // nothing was owed
        return paymentsSinceStatement >= bal - Decimal(0.5)
    }

    /// True when a payment has been made but doesn't yet cover the full statement.
    var statementPartiallyPaid: Bool {
        let bal = statementBalance
        return bal > 0 && paymentsSinceStatement > Decimal(0.5) && !statementSettled
    }

    // Cycle date helpers
    private func clampDay(_ day: Int, year: Int, month: Int) -> Int {
        let cal = Calendar.current
        var comps = DateComponents(); comps.year = year; comps.month = month
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return min(day, 28) }
        return min(day, range.upperBound - 1)
    }

    private func previousStatement(from date: Date) -> Date {
        let cal = Calendar.current
        guard let day = statementDay,
              let prevMonth = cal.date(byAdding: .month, value: -1, to: date) else { return date }
        var comps = cal.dateComponents([.year, .month], from: prevMonth)
        comps.day = clampDay(day, year: comps.year!, month: comps.month!)
        return cal.date(from: comps) ?? date
    }

    // MARK: - Projected Balance

    /// Projects this account's balance forward to `date`, applying any active
    /// scheduled transactions (income, bills, subscriptions) that fall between now and then.
    /// Used to warn when a future payment won't be covered.
    func projectedBalance(on date: Date, scheduled: [ScheduledTransaction]) -> Decimal {
        var balance = currentBalance
        let now = Date()
        guard date > now else { return balance }

        for sched in scheduled where sched.isActive && sched.account?.id == id {
            var occurrence = sched.nextDate
            var guardCount = 0
            while occurrence <= date && guardCount < 500 {
                if occurrence > now {
                    if let end = sched.endDate, occurrence > end { break }
                    balance += ExchangeRateService.shared.convert(sched.amount, from: sched.currency, to: currency)
                }
                occurrence = sched.advance(occurrence)
                guardCount += 1
            }
        }
        return balance
    }

    /// The effective floor a balance can reach before fees: `-overdraftLimit` (or 0 if none).
    var balanceFloor: Decimal {
        -(overdraftLimit ?? 0)
    }

    // MARK: - Overdraft Utility (current/savings accounts)

    /// Whether this account currently has an overdraft configured.
    var hasOverdraft: Bool {
        (overdraftLimit ?? 0) > 0 && (type == .checking || type == .savings)
    }

    /// True when the balance is negative (dipping into the overdraft).
    var isOverdrawn: Bool {
        currentBalance < 0
    }

    /// True when the balance has gone past the arranged overdraft limit.
    var isOverArrangedLimit: Bool {
        currentBalance < balanceFloor
    }

    /// Amount of the overdraft currently in use (0 when in credit).
    var overdraftUsed: Decimal {
        currentBalance < 0 ? -currentBalance : 0
    }

    /// Remaining arranged overdraft headroom (never negative).
    var overdraftRemaining: Decimal {
        max(0, (overdraftLimit ?? 0) - overdraftUsed)
    }

    /// Fraction of the arranged overdraft used (0...1+, clamped at display time).
    var overdraftUsageFraction: Double {
        guard let limit = overdraftLimit, limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: overdraftUsed / limit).doubleValue
    }

    /// True spendable amount: balance plus any arranged overdraft.
    var availableToSpend: Decimal {
        currentBalance + (overdraftLimit ?? 0)
    }

    // MARK: - Fee Estimates (informational — never posted as transactions)

    /// Estimated interest for one month of using the arranged overdraft at the current balance.
    /// Rough: uses the EAR as an annual rate divided across 12 months on the amount overdrawn.
    var estimatedMonthlyOverdraftInterest: Decimal {
        guard isOverdrawn, let ear = overdraftEAR, ear > 0 else { return 0 }
        // Interest only accrues on the portion within the arranged limit.
        let charged = min(overdraftUsed, overdraftLimit ?? overdraftUsed)
        return (charged * ear / 100) / 12
    }

    /// Estimated credit-card interest for next cycle if only `payment` is made against the statement balance.
    func estimatedCreditInterest(ifPaying payment: Decimal) -> Decimal {
        guard type == .creditCard, let apr = purchaseAPR, apr > 0 else { return 0 }
        let carried = max(0, statementBalance - payment)
        return (carried * apr / 100) / 12
    }

    /// A typical UK-style minimum payment: the greater of a fixed floor or a percentage of the balance.
    var estimatedMinimumPayment: Decimal {
        guard type == .creditCard else { return 0 }
        let bal = statementBalance
        guard bal > 0 else { return 0 }
        let percent = bal * Decimal(0.025) // 2.5%
        let floor = Decimal(5)
        return min(bal, max(floor, percent))
    }

    init(
        name: String,
        type: AccountType = .checking,
        currency: String = "USD",
        initialBalance: Decimal = 0,
        icon: String = "banknote",
        colorHex: String = "#4CAF50",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.currency = currency
        self.initialBalance = initialBalance
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = false
        self.createdAt = Date()
        self.transactions = []
        self.cachedBalance = initialBalance
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case checking = "Checking"
    case savings = "Savings"
    case creditCard = "Credit Card"
    case cash = "Cash"
    case investment = "Investment"
    case loan = "Loan"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .checking: return "building.columns"
        case .savings: return "banknote"
        case .creditCard: return "creditcard"
        case .cash: return "dollarsign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .loan: return "arrow.left.arrow.right"
        case .other: return "folder"
        }
    }
}
