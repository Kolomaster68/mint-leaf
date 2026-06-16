import SwiftUI
import SwiftData

struct AppNotification: Identifiable {
    let id = UUID()
    let stableKey: String
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    let date: Date?
    let priority: Priority
    let category: NotificationCategory

    enum Priority: Int, Comparable {
        case low = 0
        case medium = 1
        case high = 2

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum NotificationCategory: String {
        case bills
        case budgets
        case balances
        case subscriptions
        case creditCard
    }
}

@MainActor @Observable
final class NotificationManager {
    static let shared = NotificationManager()

    // MARK: - Storage keys
    private let dismissedKey = "dismissedNotifications"
    private let snoozedKey = "snoozedNotifications"

    // MARK: - Preference keys (read via UserDefaults for simplicity)
    var showBills: Bool {
        get { UserDefaults.standard.object(forKey: "notifShowBills") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifShowBills") }
    }
    var showBudgets: Bool {
        get { UserDefaults.standard.object(forKey: "notifShowBudgets") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifShowBudgets") }
    }
    var showBalances: Bool {
        get { UserDefaults.standard.object(forKey: "notifShowBalances") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifShowBalances") }
    }
    var showSubscriptions: Bool {
        get { UserDefaults.standard.object(forKey: "notifShowSubscriptions") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifShowSubscriptions") }
    }
    var showCreditCard: Bool {
        get { UserDefaults.standard.object(forKey: "notifShowCreditCard") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifShowCreditCard") }
    }
    var lowBalanceThreshold: Decimal {
        get { Decimal(UserDefaults.standard.object(forKey: "notifLowBalanceThreshold") as? Double ?? 100) }
        set { UserDefaults.standard.set(Double(truncating: newValue as NSDecimalNumber), forKey: "notifLowBalanceThreshold") }
    }
    var ccHighThreshold: Decimal {
        get { Decimal(UserDefaults.standard.object(forKey: "notifCCHighThreshold") as? Double ?? 1000) }
        set { UserDefaults.standard.set(Double(truncating: newValue as NSDecimalNumber), forKey: "notifCCHighThreshold") }
    }

    // MARK: - Dismissed keys
    private var dismissedKeys: Set<String> {
        get {
            guard let data = UserDefaults.standard.data(forKey: dismissedKey) else { return [] }
            return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: dismissedKey)
        }
    }

    // MARK: - Snoozed keys (stableKey -> snooze-until date)
    private var snoozedKeys: [String: Date] {
        get {
            guard let data = UserDefaults.standard.data(forKey: snoozedKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: snoozedKey)
        }
    }

    // MARK: - Generate notifications
    func generateNotifications(
        scheduled: [ScheduledTransaction],
        budgets: [Budget],
        accounts: [Account]
    ) -> [AppNotification] {
        var items: [AppNotification] = []
        let calendar = Calendar.current
        let today = Date()
        let sevenDays = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let threeDays = calendar.date(byAdding: .day, value: 3, to: today) ?? today

        // Bills and subscriptions due
        if showBills {
            for item in scheduled where item.isActive && !item.isSubscription {
                if let notif = billNotification(item, today: today, threeDays: threeDays, sevenDays: sevenDays) {
                    items.append(notif)
                }
            }
        }

        if showSubscriptions {
            for item in scheduled where item.isActive && item.isSubscription {
                if let notif = billNotification(item, today: today, threeDays: threeDays, sevenDays: sevenDays) {
                    items.append(notif)
                }
            }
        }

        // Budget warnings
        if showBudgets {
            for budget in budgets {
                for item in budget.items {
                    guard let category = item.category else { continue }
                    if item.progress >= 1.0 {
                        items.append(AppNotification(
                            stableKey: "budget-exceeded-\(category.name)",
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .red,
                            title: "\(category.name) budget exceeded",
                            message: "Spent \(CurrencyFormatter.shared.format(item.spent)) of \(CurrencyFormatter.shared.format(item.amount)) budget",
                            date: nil,
                            priority: .high,
                            category: .budgets
                        ))
                    } else if item.progress >= 0.8 {
                        items.append(AppNotification(
                            stableKey: "budget-warning-\(category.name)",
                            icon: "chart.pie.fill",
                            iconColor: .orange,
                            title: "\(category.name) budget at \(Int(item.progress * 100))%",
                            message: "\(CurrencyFormatter.shared.format(item.remaining)) remaining of \(CurrencyFormatter.shared.format(item.amount))",
                            date: nil,
                            priority: .medium,
                            category: .budgets
                        ))
                    }
                }
            }
        }

        // Balance warnings
        if showBalances {
            for account in accounts where !account.isArchived {
                if account.type != .creditCard {
                    if account.isOverArrangedLimit && account.hasOverdraft {
                        // Past the arranged overdraft → highest priority, name the fee.
                        var msg = "Balance \(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency)) is past your \(CurrencyFormatter.shared.format(account.overdraftLimit ?? 0, currency: account.currency)) overdraft."
                        if let fee = account.unarrangedOverdraftFee, fee > 0 {
                            msg += " May incur a \(CurrencyFormatter.shared.format(fee, currency: account.currency)) fee."
                        }
                        items.append(AppNotification(
                            stableKey: "over-limit-\(account.name)",
                            icon: "exclamationmark.octagon.fill",
                            iconColor: .red,
                            title: "\(account.name) over overdraft limit",
                            message: msg,
                            date: nil,
                            priority: .high,
                            category: .balances
                        ))
                    } else if account.currentBalance < 0 {
                        var msg = "Balance: \(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))"
                        if account.hasOverdraft, account.estimatedMonthlyOverdraftInterest >= 1 {
                            msg += " — using your overdraft, about \(CurrencyFormatter.shared.format(account.estimatedMonthlyOverdraftInterest, currency: account.currency)) interest this month."
                        }
                        items.append(AppNotification(
                            stableKey: "negative-\(account.name)",
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .red,
                            title: account.hasOverdraft ? "\(account.name) is in its overdraft" : "\(account.name) is negative",
                            message: msg,
                            date: nil,
                            priority: account.hasOverdraft ? .medium : .high,
                            category: .balances
                        ))
                    } else if account.currentBalance < lowBalanceThreshold && account.type != .loan {
                        items.append(AppNotification(
                            stableKey: "low-balance-\(account.name)",
                            icon: "exclamationmark.circle",
                            iconColor: .orange,
                            title: "\(account.name) balance is low",
                            message: "Balance: \(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))",
                            date: nil,
                            priority: .medium,
                            category: .balances
                        ))
                    }
                } else {
                    if abs(account.currentBalance) > ccHighThreshold {
                        items.append(AppNotification(
                            stableKey: "cc-high-\(account.name)",
                            icon: "creditcard.fill",
                            iconColor: .orange,
                            title: "\(account.name) debt is high",
                            message: "Owed: \(CurrencyFormatter.shared.format(abs(account.currentBalance), currency: account.currency))",
                            date: nil,
                            priority: .medium,
                            category: .balances
                        ))
                    }
                }
            }
        }

        // Credit card statement & payment lifecycle
        if showCreditCard {
            let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            for card in accounts where !card.isArchived && card.hasBillingCycle {
                items.append(contentsOf: creditCardNotifications(
                    card: card,
                    accountsByID: accountsByID,
                    scheduled: scheduled,
                    today: today,
                    calendar: calendar
                ))
            }
        }

        // Paused subscriptions
        if showSubscriptions {
            let pausedCount = scheduled.filter { $0.isSubscription && !$0.isActive }.count
            if pausedCount > 0 {
                items.append(AppNotification(
                    stableKey: "paused-subs",
                    icon: "pause.circle",
                    iconColor: .secondary,
                    title: "\(pausedCount) paused subscription\(pausedCount == 1 ? "" : "s")",
                    message: "Review your paused subscriptions to see if you still need them.",
                    date: nil,
                    priority: .low,
                    category: .subscriptions
                ))
            }
        }

        // Auto-resolve: clean dismissed/snoozed keys that no longer have matching notifications
        let activeKeys = Set(items.map(\.stableKey))
        autoResolve(activeKeys: activeKeys)

        // Filter out dismissed and snoozed
        let dismissed = dismissedKeys
        let snoozed = snoozedKeys

        return items
            .filter { notif in
                if dismissed.contains(notif.stableKey) { return false }
                if let snoozeUntil = snoozed[notif.stableKey], snoozeUntil > today { return false }
                return true
            }
            .sorted { $0.priority > $1.priority }
    }

    // MARK: - Badge count (visible notifications with medium+ priority)
    func badgeCount(
        scheduled: [ScheduledTransaction],
        budgets: [Budget],
        accounts: [Account]
    ) -> Int {
        generateNotifications(scheduled: scheduled, budgets: budgets, accounts: accounts)
            .filter { $0.priority >= .medium }
            .count
    }

    // MARK: - Actions
    func dismiss(_ notif: AppNotification) {
        var keys = dismissedKeys
        keys.insert(notif.stableKey)
        dismissedKeys = keys
    }

    func dismissAll(_ notifications: [AppNotification]) {
        var keys = dismissedKeys
        for notif in notifications {
            keys.insert(notif.stableKey)
        }
        dismissedKeys = keys
    }

    func snooze(_ notif: AppNotification, hours: Int = 24) {
        var snoozed = snoozedKeys
        snoozed[notif.stableKey] = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
        snoozedKeys = snoozed
    }

    func restoreAll() {
        dismissedKeys = []
        snoozedKeys = [:]
    }

    var hasDismissedOrSnoozed: Bool {
        !dismissedKeys.isEmpty || !snoozedKeys.isEmpty
    }

    // MARK: - Auto-resolve
    private func autoResolve(activeKeys: Set<String>) {
        // Remove dismissed keys for conditions that no longer exist
        let dismissed = dismissedKeys
        let stale = dismissed.subtracting(activeKeys)
        if !stale.isEmpty {
            dismissedKeys = dismissed.subtracting(stale)
        }

        // Remove expired or stale snoozed keys
        var snoozed = snoozedKeys
        let now = Date()
        var changed = false
        for (key, until) in snoozed {
            if until <= now || !activeKeys.contains(key) {
                snoozed.removeValue(forKey: key)
                changed = true
            }
        }
        if changed {
            snoozedKeys = snoozed
        }
    }

    // MARK: - Credit Card Payment Lifecycle
    private func creditCardNotifications(
        card: Account,
        accountsByID: [UUID: Account],
        scheduled: [ScheduledTransaction],
        today: Date,
        calendar: Calendar
    ) -> [AppNotification] {
        var result: [AppNotification] = []

        let statementBalance = card.statementBalance
        guard statementBalance > 0 else { return result } // nothing owed → nothing to chase
        guard let dueDate = card.nextPaymentDueDate() else { return result }

        let cycleKey0 = Self.cycleKey(for: dueDate)

        // Auto-reconcile: if payments since the statement closed cover it, the
        // payment was made — confirm it and skip all the due/overdue chasing.
        if card.statementSettled {
            result.append(AppNotification(
                stableKey: "cc-paid-\(card.id)-\(cycleKey0)",
                icon: "checkmark.circle.fill",
                iconColor: .green,
                title: "\(card.name) payment received",
                message: "Your \(CurrencyFormatter.shared.format(card.paymentsSinceStatement, currency: card.currency)) payment cleared this statement.",
                date: nil,
                priority: .low,
                category: .creditCard
            ))
            return result
        }

        let startToday = calendar.startOfDay(for: today)
        let startDue = calendar.startOfDay(for: dueDate)
        let daysUntil = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        // Chase the amount that's actually still outstanding (handles partial payments).
        let outstanding = card.statementRemaining
        let amountStr = CurrencyFormatter.shared.format(outstanding, currency: card.currency)
        let dueStr = Self.shortDateString(dueDate)

        // Statement / due reminders. One notification per state, keyed per cycle so it auto-resolves.
        let cycleKey = cycleKey0
        if daysUntil < 0 {
            result.append(AppNotification(
                stableKey: "cc-overdue-\(card.id)-\(cycleKey)",
                icon: "exclamationmark.octagon.fill",
                iconColor: .red,
                title: "\(card.name) payment overdue",
                message: "\(amountStr) was due \(dueStr) — late fees may apply",
                date: dueDate,
                priority: .high,
                category: .creditCard
            ))
        } else if daysUntil == 0 {
            result.append(AppNotification(
                stableKey: "cc-due-today-\(card.id)-\(cycleKey)",
                icon: "creditcard.fill",
                iconColor: .red,
                title: "\(card.name) payment due today",
                message: "\(amountStr) due today",
                date: dueDate,
                priority: .high,
                category: .creditCard
            ))
        } else if daysUntil <= 5 {
            result.append(AppNotification(
                stableKey: "cc-due-soon-\(card.id)-\(cycleKey)",
                icon: "creditcard",
                iconColor: .orange,
                title: "\(card.name) payment due soon",
                message: "\(amountStr) due in \(daysUntil) day\(daysUntil == 1 ? "" : "s") (\(dueStr))",
                date: dueDate,
                priority: .medium,
                category: .creditCard
            ))
        }

        // Insufficient-funds warning: only worth raising within ~10 days of the due date.
        if daysUntil >= 0 && daysUntil <= 10,
           let sourceID = card.paymentSourceAccountID,
           let source = accountsByID[sourceID] {
            let projected = source.projectedBalance(on: dueDate, scheduled: scheduled)
            let afterPayment = projected - outstanding
            if afterPayment < source.balanceFloor {
                let shortfall = source.balanceFloor - afterPayment
                let projectedStr = CurrencyFormatter.shared.format(projected, currency: source.currency)
                let shortfallStr = CurrencyFormatter.shared.format(abs(shortfall), currency: source.currency)
                var feeNote = "Top up to avoid fees."
                if let fee = source.unarrangedOverdraftFee, fee > 0 {
                    feeNote = "Likely a \(CurrencyFormatter.shared.format(fee, currency: source.currency)) unarranged overdraft fee — top up to avoid it."
                }
                result.append(AppNotification(
                    stableKey: "cc-funds-\(card.id)-\(cycleKey)",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red,
                    title: "\(source.name) may not cover \(card.name)",
                    message: "\(amountStr) due \(dueStr). Projected balance then: \(projectedStr) — short by \(shortfallStr). \(feeNote)",
                    date: dueDate,
                    priority: .high,
                    category: .creditCard
                ))
            }
        }

        // Interest nudge: if the card charges interest and isn't going to be cleared, suggest paying in full.
        if let apr = card.purchaseAPR, apr > 0 {
            let interest = card.estimatedCreditInterest(ifPaying: card.estimatedMinimumPayment)
            if interest >= 1 {
                let interestStr = CurrencyFormatter.shared.format(interest, currency: card.currency)
                let minStr = CurrencyFormatter.shared.format(card.estimatedMinimumPayment, currency: card.currency)
                result.append(AppNotification(
                    stableKey: "cc-interest-\(card.id)-\(cycleKey)",
                    icon: "percent",
                    iconColor: .orange,
                    title: "Pay \(card.name) in full to avoid interest",
                    message: "Paying only the \(minStr) minimum would cost about \(interestStr) interest next cycle at \(apr)% APR.",
                    date: nil,
                    priority: .low,
                    category: .creditCard
                ))
            }
        }

        return result
    }

    /// A stable per-cycle suffix so a notification for one statement period
    /// auto-resolves once the cycle rolls over (different due date → different key).
    private static func cycleKey(for dueDate: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMM"
        return f.string(from: dueDate)
    }

    // MARK: - Helpers
    private func billNotification(
        _ item: ScheduledTransaction,
        today: Date,
        threeDays: Date,
        sevenDays: Date
    ) -> AppNotification? {
        let cat: AppNotification.NotificationCategory = item.isSubscription ? .subscriptions : .bills

        let id = item.id.uuidString
        if item.nextDate <= today {
            return AppNotification(
                stableKey: "overdue-\(id)",
                icon: "exclamationmark.circle.fill",
                iconColor: .red,
                title: "\(item.title) is overdue",
                message: "Was due \(Self.relativeDateString(item.nextDate)) — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                date: item.nextDate,
                priority: .high,
                category: cat
            )
        } else if item.nextDate <= threeDays {
            return AppNotification(
                stableKey: "due-soon-\(id)",
                icon: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar.badge.clock",
                iconColor: .orange,
                title: "\(item.title) due soon",
                message: "Due \(Self.relativeDateString(item.nextDate)) — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                date: item.nextDate,
                priority: .high,
                category: cat
            )
        } else if item.nextDate <= sevenDays {
            return AppNotification(
                stableKey: "coming-up-\(id)",
                icon: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar",
                iconColor: .blue,
                title: "\(item.title) coming up",
                message: "Due \(Self.shortDateString(item.nextDate)) — \(CurrencyFormatter.shared.format(abs(item.amount)))",
                date: item.nextDate,
                priority: .medium,
                category: cat
            )
        }
        return nil
    }

    private static func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
