import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduledTransactions: [ScheduledTransaction]
    @State private var showAllSubscriptions = false

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
            .filter { $0.isActive && $0.nextDate <= sevenDays }
            .sorted { $0.nextDate < $1.nextDate }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroBalance
                summaryCards
                if !upcomingBills.isEmpty {
                    upcomingBillsCard
                }
                if !activeSubscriptions.isEmpty {
                    subscriptionsCard
                }
                recentTransactionsList
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Overview")
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
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Text("Net Worth")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent(for: scheme))
                Text(CurrencyFormatter.shared.format(totalBalance))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.bold())
                    Text("\(isPositive ? "+" : "")\(CurrencyFormatter.shared.format(netChange)) this month")
                        .font(.subheadline)
                }
                .foregroundStyle(isPositive ? .green : .red)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Liabilities")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.shared.format(totalLiabilities))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.red)
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
                color: .green,
                changePercent: changePercent(current: monthIncome, previous: prevIncome)
            )
            SummaryCard(
                title: "Expenses (30d)",
                amount: monthExpenses,
                icon: "arrow.down.circle",
                color: .red,
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
                            item.nextDate <= Date() ? Color.red
                            : item.nextDate <= Calendar.current.date(byAdding: .day, value: 3, to: Date())! ? Color.orange
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
                        .foregroundStyle(item.nextDate <= Date() ? .red : .secondary)
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
        let monthlyTotal = subs.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
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
                .overlay(AppTheme.accent(for: scheme).opacity(0.1))

            let sortedSubs = subs.sorted(by: { $0.monthlyEquivalent > $1.monthlyEquivalent })
            let visibleSubs = showAllSubscriptions ? sortedSubs : Array(sortedSubs.prefix(5))

            ForEach(visibleSubs, id: \.id) { sub in
                HStack {
                    Text(sub.title)
                        .font(.body)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(sub.amount))
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
                        .overlay(AppTheme.accent(for: scheme).opacity(0.1))
                }
            }
        }
        .premiumCard()
    }
}

struct SummaryCard: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
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
                    .foregroundStyle(pct >= 0 ? (color == .green ? .green : .red) : (color == .green ? .red : .green))
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
