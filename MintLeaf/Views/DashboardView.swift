import SwiftUI
import SwiftData

// MARK: - Dashboard Card Definitions

enum DashboardCard: String, CaseIterable, Identifiable, Codable {
    case heroBalance = "Net Worth"
    case creditCardDue = "Credit Card Payments"
    case financialHealth = "Financial Health"
    case summaryCards = "Income & Expenses"
    case upcomingBills = "Upcoming Bills"
    case subscriptions = "Subscriptions"
    case recentTransactions = "Recent Transactions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .heroBalance: return "banknote"
        case .creditCardDue: return "creditcard"
        case .summaryCards: return "arrow.up.arrow.down"
        case .financialHealth: return "heart.text.clipboard"
        case .upcomingBills: return "calendar.badge.clock"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .recentTransactions: return "list.bullet"
        }
    }
}

// MARK: - Dashboard Configuration Manager

@MainActor @Observable
final class DashboardConfig {
    static let shared = DashboardConfig()

    private let orderKey = "dashboardCardOrder"
    private let hiddenKey = "dashboardHiddenCards"

    // Stored properties so @Observable can track them
    var cardOrder: [DashboardCard]
    var hiddenCards: Set<DashboardCard>

    private init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: orderKey),
           let decoded = try? JSONDecoder().decode([DashboardCard].self, from: data) {
            let missing = DashboardCard.allCases.filter { !decoded.contains($0) }
            self.cardOrder = decoded + missing
        } else {
            self.cardOrder = DashboardCard.allCases
        }

        if let data = UserDefaults.standard.data(forKey: hiddenKey),
           let decoded = try? JSONDecoder().decode(Set<DashboardCard>.self, from: data) {
            self.hiddenCards = decoded
        } else {
            self.hiddenCards = []
        }
    }

    func isVisible(_ card: DashboardCard) -> Bool {
        !hiddenCards.contains(card)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(cardOrder), forKey: orderKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(hiddenCards), forKey: hiddenKey)
    }

    func resetToDefaults() {
        cardOrder = DashboardCard.allCases
        hiddenCards = []
        UserDefaults.standard.removeObject(forKey: orderKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduledTransactions: [ScheduledTransaction]
    @State private var showAllSubscriptions = false
    @State private var showingCustomise = false
    private let config = DashboardConfig.shared

    /// Called when the user taps "Review" on the data-health banner.
    var onReviewDataHealth: (() -> Void)? = nil

    /// Accounts whose cached balance has drifted from opening balance + transactions.
    private var driftedAccounts: [Account] {
        accounts.filter { account in
            let expected = account.initialBalance + account.transactions.reduce(Decimal.zero) { $0 + $1.amount }
            return abs(account.currentBalance - expected) >= Decimal(0.01)
        }
    }

    private var recentTransactions: [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return allTransactions.filter { $0.date > cutoff }
    }

    private var totalBalance: Decimal {
        accounts.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    private var monthIncome: Decimal {
        recentTransactions.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var monthExpenses: Decimal {
        recentTransactions.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    private var previousPeriodTransactions: [Transaction] {
        let now = Date()
        let cutoff30 = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let cutoff60 = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        return allTransactions.filter { $0.date > cutoff60 && $0.date <= cutoff30 }
    }

    private var prevIncome: Decimal {
        previousPeriodTransactions.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var prevExpenses: Decimal {
        previousPeriodTransactions.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    private var activeSubscriptions: [ScheduledTransaction] {
        scheduledTransactions.filter { $0.isSubscription && $0.isActive }
    }

    private var upcomingBills: [ScheduledTransaction] {
        let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return scheduledTransactions
            .filter { $0.isActive && !$0.isSubscription && $0.nextDate <= sevenDays }
            .sorted { $0.nextDate < $1.nextDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Data-health banner: surfaces a balance discrepancy where the
                // user looks daily, with a one-tap route to fix it.
                if !driftedAccounts.isEmpty {
                    dataHealthBanner
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // When a credit card payment is urgent, float it to the very top
                // regardless of the user's saved order, with an attention border.
                if hasUrgentCreditCardPayment && config.isVisible(.creditCardDue) {
                    creditCardDueCard
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(AppTheme.warning, lineWidth: scheme == .dark ? 2 : 3)
                        )
                        .shadow(color: AppTheme.warning.opacity(scheme == .dark ? 0 : 0.25), radius: 6, y: 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                ForEach(config.cardOrder) { card in
                    if config.isVisible(card) {
                        // Skip the credit card card here if it's been promoted above
                        if !(card == .creditCardDue && hasUrgentCreditCardPayment) {
                            cardView(for: card)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingCustomise = true
                } label: {
                    Label("Customise", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingCustomise) {
            DashboardCustomiseSheet()
        }
    }

    @ViewBuilder
    private func cardView(for card: DashboardCard) -> some View {
        switch card {
        case .heroBalance:
            heroBalance
        case .creditCardDue:
            if !creditCardsWithCycle.isEmpty {
                creditCardDueCard
            }
        case .summaryCards:
            summaryCards
        case .financialHealth:
            financialHealthCard
        case .upcomingBills:
            if !upcomingBills.isEmpty {
                upcomingBillsCard
            }
        case .subscriptions:
            if !activeSubscriptions.isEmpty {
                subscriptionsCard
            }
        case .recentTransactions:
            recentTransactionsList
        }
    }

    private var totalAssets: Decimal {
        accounts.filter { !$0.isArchived && $0.currentBalance > 0 }.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    private var totalLiabilities: Decimal {
        accounts.filter { !$0.isArchived && $0.currentBalance < 0 }.reduce(Decimal.zero) { $0 + abs($1.currentBalance) }
    }

    private var heroBalance: some View {
        let netChange = monthIncome - monthExpenses
        let isPositive = netChange >= 0

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.shared.format(totalAssets))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.income)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Text("Net Worth")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent(for: scheme))
                Text(CurrencyFormatter.shared.format(totalBalance))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.bold())
                    Text("\(isPositive ? "+" : "")\(CurrencyFormatter.shared.format(netChange)) this month")
                        .font(.subheadline)
                }
                .foregroundStyle(isPositive ? AppTheme.income : AppTheme.expense)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Liabilities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.shared.format(totalLiabilities))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.expense)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .premiumCard()
    }

    private func changePercent(current: Decimal, previous: Decimal) -> Double? {
        guard previous != 0 else { return nil }
        let diff = current - previous
        return NSDecimalNumber(decimal: diff / previous * 100).doubleValue
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Income (30d)",
                amount: monthIncome,
                icon: "arrow.up.circle",
                color: AppTheme.income,
                isIncome: true,
                changePercent: changePercent(current: monthIncome, previous: prevIncome)
            )
            SummaryCard(
                title: "Expenses (30d)",
                amount: monthExpenses,
                icon: "arrow.down.circle",
                color: AppTheme.expense,
                isIncome: false,
                changePercent: changePercent(current: monthExpenses, previous: prevExpenses)
            )
        }
    }

    private var upcomingBillsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Upcoming", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Text("Next 7 days")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }

            ForEach(upcomingBills.prefix(5)) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            item.nextDate <= Date() ? AppTheme.expense
                            : item.nextDate <= Calendar.current.date(byAdding: .day, value: 3, to: Date())! ? AppTheme.warning
                            : AppTheme.accent(for: scheme),
                            in: RoundedRectangle(cornerRadius: 7)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                        Group {
                            if item.nextDate <= Date() {
                                Text("Overdue")
                            } else {
                                Text(item.nextDate, style: .date)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(item.nextDate <= Date() ? AppTheme.expense : .secondary)
                    }

                    Spacer()

                    Text(CurrencyFormatter.shared.format(abs(item.amount)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }

            if upcomingBills.count > 5 {
                Text("+\(upcomingBills.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }
        }
        .premiumCard()
    }

    private var subscriptionsCard: some View {
        let subs = activeSubscriptions
        let monthlyTotal = subs.reduce(Decimal.zero) { $0 + $1.convertedMonthlyEquivalent }
        let yearlyTotal = monthlyTotal * 12

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Subscriptions", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(subs.count) active")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Monthly")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(monthlyTotal))
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Yearly")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(yearlyTotal))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .overlay(AppTheme.divider(for: scheme))

            let sortedSubs = subs.sorted(by: { $0.convertedMonthlyEquivalent > $1.convertedMonthlyEquivalent })
            let visibleSubs = showAllSubscriptions ? sortedSubs : Array(sortedSubs.prefix(5))

            ForEach(visibleSubs, id: \.id) { sub in
                HStack {
                    Text(sub.title)
                        .font(.body)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(sub.convertedAmount))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("/\(sub.frequency == .yearly ? "yr" : "mo")")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            if subs.count > 5 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllSubscriptions.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllSubscriptions ? "Show less" : "+\(subs.count - 5) more")
                            .font(.subheadline)
                        Image(systemName: showAllSubscriptions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(AppTheme.accent(for: scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .premiumCard()
    }

    // MARK: - Data Health Banner

    private var dataHealthBanner: some View {
        let names = driftedAccounts.map(\.name)
        let detail: String = {
            if names.count == 1 { return "\(names[0])'s balance doesn't match its transactions." }
            return "\(names.count) account balances don't match their transactions."
        }()

        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Balance needs attention")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                onReviewDataHealth?()
            } label: {
                Text("Review")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.warning)
        }
        .padding(16)
        .background(AppTheme.warning.opacity(scheme == .dark ? 0.12 : 0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.warning.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Credit Card Payment Due Card

    private var creditCardsWithCycle: [Account] {
        accounts.filter { !$0.isArchived && $0.hasBillingCycle }
    }

    /// True when any credit card has an outstanding statement balance due within 5 days (or overdue).
    private var hasUrgentCreditCardPayment: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return creditCardsWithCycle.contains { card in
            guard card.statementBalance > 0, !card.statementSettled,
                  let due = card.nextPaymentDueDate() else { return false }
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 99
            return days <= 5
        }
    }

    private var creditCardDueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Credit Card Payments", systemImage: "creditcard")
                    .font(.headline)
                Spacer()
            }

            ForEach(creditCardsWithCycle) { card in
                let due = card.nextPaymentDueDate()
                let statementBal = card.statementBalance
                let settled = card.statementSettled && statementBal > 0
                let partial = card.statementPartiallyPaid
                let daysUntil = due.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0)).day ?? 0 }

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: card.icon)
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(hex: card.colorHex), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(.subheadline.weight(.medium))
                            if settled {
                                Label("Paid — statement cleared", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.income)
                            } else if let due, let days = daysUntil {
                                Text(partial
                                     ? "Part-paid · \(dueText(due: due, days: days))"
                                     : dueText(due: due, days: days))
                                    .font(.caption)
                                    .foregroundStyle(days <= 3 ? AppTheme.warning : .secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if settled {
                                Text(CurrencyFormatter.shared.format(0, currency: card.currency))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(AppTheme.income)
                                Text("nothing due")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(CurrencyFormatter.shared.format(card.statementRemaining, currency: card.currency))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(card.statementRemaining > 0 ? AppTheme.expense : .secondary)
                                Text(partial ? "still owed" : "statement balance")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let unbilled = card.unbilledBalance
                    if unbilled > 0 {
                        HStack {
                            Text("Unbilled since statement")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(unbilled, currency: card.currency))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }

                    let minInterest = card.estimatedCreditInterest(ifPaying: card.estimatedMinimumPayment)
                    if !settled, minInterest >= 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("Pay in full — minimum payment would cost ~\(CurrencyFormatter.shared.format(minInterest, currency: card.currency)) interest")
                            Spacer()
                        }
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warning)
                    }
                }

                if card.id != creditCardsWithCycle.last?.id {
                    Divider().overlay(AppTheme.divider(for: scheme))
                }
            }
        }
        .premiumCard()
    }

    private func dueText(due: Date, days: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        let dateStr = df.string(from: due)
        if days < 0 {
            return "Was due \(dateStr)"
        } else if days == 0 {
            return "Due today (\(dateStr))"
        } else if days == 1 {
            return "Due tomorrow (\(dateStr))"
        } else {
            return "Due in \(days) days (\(dateStr))"
        }
    }

    // MARK: - Financial Health Card

    private var savingsRate: Double {
        guard monthIncome > 0 else { return 0 }
        let saved = monthIncome - monthExpenses
        return NSDecimalNumber(decimal: saved / monthIncome * 100).doubleValue
    }

    private var debtToAssetRatio: Double {
        guard totalAssets > 0 else { return totalLiabilities > 0 ? 100 : 0 }
        return NSDecimalNumber(decimal: totalLiabilities / totalAssets * 100).doubleValue
    }

    private var healthScore: Int {
        var score = 50 // Start at 50

        // Savings rate component (0-30 points)
        let sr = savingsRate
        if sr >= 20 { score += 30 }
        else if sr >= 10 { score += 20 }
        else if sr > 0 { score += 10 }
        else if sr < -10 { score -= 15 }

        // Debt ratio component (0-20 points)
        let dr = debtToAssetRatio
        if dr <= 10 { score += 20 }
        else if dr <= 30 { score += 10 }
        else if dr > 60 { score -= 10 }

        return max(0, min(100, score))
    }

    private var healthGrade: (label: String, color: Color) {
        switch healthScore {
        case 80...100: return ("Excellent", AppTheme.income)
        case 60..<80: return ("Good", Color(red: 0.40, green: 0.75, blue: 0.30))
        case 40..<60: return ("Fair", AppTheme.warning)
        default: return ("Needs Work", AppTheme.expense)
        }
    }

    private var financialHealthCard: some View {
        let grade = healthGrade

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Financial Health", systemImage: "heart.text.clipboard")
                    .font(.headline)
                Spacer()
                Text(grade.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(grade.color)
            }

            // Score bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(healthScore)/100")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(grade.color)
                            .frame(width: geo.size.width * CGFloat(healthScore) / 100.0)
                    }
                }
                .frame(height: 8)
            }

            Divider()
                .overlay(AppTheme.divider(for: scheme))

            // Metrics
            HStack(spacing: 16) {
                healthMetric(
                    title: "Savings Rate",
                    value: String(format: "%.0f%%", savingsRate),
                    icon: "leaf.fill",
                    good: savingsRate >= 10
                )

                healthMetric(
                    title: "Debt Ratio",
                    value: String(format: "%.0f%%", debtToAssetRatio),
                    icon: "chart.bar.fill",
                    good: debtToAssetRatio <= 30
                )

                healthMetric(
                    title: "Net Monthly",
                    value: CurrencyFormatter.shared.format(monthIncome - monthExpenses),
                    icon: "plusminus",
                    good: monthIncome >= monthExpenses
                )
            }
        }
        .premiumCard()
    }

    private func healthMetric(title: String, value: String, icon: String, good: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(good ? AppTheme.income : AppTheme.warning)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentTransactionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                Spacer()
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent(for: scheme))
            }

            if recentTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions Yet",
                    systemImage: "tray",
                    description: Text("Add an account and start tracking your finances.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(recentTransactions.sorted(by: { $0.date > $1.date }).prefix(10), id: \.id) { transaction in
                    TransactionRow(transaction: transaction, showAccount: true)
                    Divider()
                        .overlay(AppTheme.divider(for: scheme).opacity(0.5))
                }
            }
        }
        .premiumCard()
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    var isIncome: Bool = false
    var changePercent: Double? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Text(CurrencyFormatter.shared.format(amount))
                    .font(.title.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            if let pct = changePercent {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.body.bold())
                        Text(String(format: "%+.0f%%", pct))
                            .font(.title2.bold())
                    }
                    .foregroundStyle(pct >= 0 ? (isIncome ? AppTheme.income : AppTheme.expense) : (isIncome ? AppTheme.expense : AppTheme.income))
                    Text("vs prior 30d")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No prior data")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .premiumCard()
    }
}

// MARK: - Customise Sheet

struct DashboardCustomiseSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var cardOrder: [DashboardCard] = []
    @State private var hiddenCards: Set<DashboardCard> = []

    private let config = DashboardConfig.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cardOrder) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Image(systemName: card.icon)
                                .font(.body)
                                .foregroundStyle(hiddenCards.contains(card) ? Color.secondary.opacity(0.4) : AppTheme.accent(for: scheme))
                                .frame(width: 24)

                            Text(card.rawValue)
                                .font(.subheadline.weight(.medium))
                                .opacity(hiddenCards.contains(card) ? 0.5 : 1.0)

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if hiddenCards.contains(card) {
                                        hiddenCards.remove(card)
                                    } else {
                                        hiddenCards.insert(card)
                                    }
                                }
                            } label: {
                                Image(systemName: hiddenCards.contains(card) ? "eye.slash" : "eye")
                                    .font(.subheadline)
                                    .foregroundStyle(hiddenCards.contains(card) ? Color.secondary.opacity(0.4) : AppTheme.accent(for: scheme))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        cardOrder.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Drag to reorder, tap the eye to show or hide")
                } footer: {
                    Text("Hidden cards won't appear on your dashboard but their data is still tracked.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .premiumList()
            .navigationTitle("Customise Dashboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Reset to Defaults") {
                        withAnimation {
                            cardOrder = DashboardCard.allCases
                            hiddenCards = []
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.cardOrder = cardOrder
                        config.hiddenCards = hiddenCards
                        config.save()
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .onAppear {
            cardOrder = config.cardOrder
            hiddenCards = config.hiddenCards
        }
        .macOSSheet(width: 460, height: 440)
    }
}
