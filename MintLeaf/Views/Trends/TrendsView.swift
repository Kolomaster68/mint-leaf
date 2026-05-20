import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var timeRange: TimeRange = .sixMonths
    @State private var chartType: ChartType = .spending
    @State private var selectedCategory: String?

    enum TimeRange: String, CaseIterable, Identifiable {
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case allTime = "All"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .allTime: return 3650
            }
        }
    }

    enum ChartType: String, CaseIterable, Identifiable {
        case spending = "Spending"
        case incomeVsExpense = "Income vs Expense"
        case balance = "Balance"
        case categories = "By Category"

        var id: String { rawValue }
    }

    private var allTransactions: [Transaction] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        return accounts.flatMap { $0.transactions }.filter { $0.date >= cutoff }
    }

    private var totalIncome: Decimal {
        allTransactions.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var totalExpenses: Decimal {
        allTransactions.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    private var netChange: Decimal {
        totalIncome - totalExpenses
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OutlineSegmentedPicker(selection: $chartType, label: "Chart")
                    .padding(.horizontal)

                OutlineSegmentedPicker(selection: $timeRange, label: "Time Range")
                    .padding(.horizontal)

                periodSummary
                    .padding(.horizontal)

                switch chartType {
                case .spending:
                    spendingChart
                case .incomeVsExpense:
                    incomeVsExpenseChart
                case .balance:
                    balanceChart
                case .categories:
                    categoryBreakdown
                }
            }
            .padding()
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Trends")
    }

    private var periodSummary: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Income", value: totalIncome, color: .green, icon: "arrow.down.circle.fill")
            summaryCard(title: "Expenses", value: totalExpenses, color: .red, icon: "arrow.up.circle.fill")
            summaryCard(title: "Net", value: netChange, color: netChange >= 0 ? .green : .red, icon: netChange >= 0 ? "plus.circle.fill" : "minus.circle.fill", showSign: true)
        }
    }

    private func summaryCard(title: String, value: Decimal, color: Color, icon: String, showSign: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text((showSign && value > 0 ? "+" : "") + CurrencyFormatter.shared.format(value))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(showSign ? color : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.2), lineWidth: 1))
    }

    private struct MonthData: Identifiable {
        let id: Date
        let month: String
        let income: Decimal
        let expenses: Decimal
        var monthDate: Date { id }
    }

    private var monthlyData: [MonthData] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: allTransactions) { txn -> Date in
            let comps = cal.dateComponents([.year, .month], from: txn.date)
            return cal.date(from: comps) ?? txn.date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return grouped.map { key, txns in
            let income = txns.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
            let expenses = txns.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
            return MonthData(id: key, month: formatter.string(from: key), income: income, expenses: expenses)
        }
        .sorted { $0.monthDate < $1.monthDate }
    }

    private var spendingChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Monthly Spending")
                    .font(.headline)
                Spacer()
                if monthlyData.count > 1 {
                    let avg = totalExpenses / Decimal(monthlyData.count)
                    Text("Avg: \(CurrencyFormatter.shared.format(avg))/mo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let avgValue = monthlyData.isEmpty ? 0.0 : Double(truncating: (totalExpenses / Decimal(monthlyData.count)) as NSDecimalNumber)

            Chart {
                ForEach(monthlyData) { item in
                    let val = Double(truncating: item.expenses as NSDecimalNumber)
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", min(val, avgValue))
                    )
                    .foregroundStyle(AppTheme.accent(for: scheme).gradient)
                    .cornerRadius(4)

                    if val > avgValue {
                        BarMark(
                            x: .value("Month", item.month),
                            yStart: .value("Avg", avgValue),
                            yEnd: .value("Amount", val)
                        )
                        .foregroundStyle(Color.red.opacity(0.6).gradient)
                        .cornerRadius(4)
                    }
                }
                RuleMark(y: .value("Average", avgValue))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.orange.opacity(0.8))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(shortCurrency(avgValue))")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 260)

            if let highest = monthlyData.max(by: { $0.expenses < $1.expenses }),
               let lowest = monthlyData.min(by: { $0.expenses < $1.expenses }),
               monthlyData.count > 1 {
                HStack {
                    Label("Lowest: \(CurrencyFormatter.shared.format(lowest.expenses)) (\(lowest.month))", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Label("Highest: \(CurrencyFormatter.shared.format(highest.expenses)) (\(highest.month))", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    private struct IvEEntry: Identifiable {
        let id = UUID()
        let month: String
        let type: String
        let amount: Double
    }

    private var incomeVsExpenseEntries: [IvEEntry] {
        monthlyData.flatMap { item -> [IvEEntry] in
            [
                IvEEntry(month: item.month, type: "Income", amount: Double(truncating: item.income as NSDecimalNumber)),
                IvEEntry(month: item.month, type: "Expenses", amount: Double(truncating: item.expenses as NSDecimalNumber))
            ]
        }
    }

    private var incomeVsExpenseChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Income vs Expenses")
                .font(.headline)

            let entries = incomeVsExpenseEntries

            Chart(entries) { entry in
                BarMark(
                    x: .value("Month", entry.month),
                    y: .value("Amount", entry.amount)
                )
                .foregroundStyle(entry.type == "Income" ? Color.green.gradient : Color.red.gradient)
                .position(by: .value("Type", entry.type))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Income": Color.green, "Expenses": Color.red])
            .chartLegend(position: .top, alignment: .trailing)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 260)

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 16) {
                ForEach(monthlyData.suffix(3), id: \.monthDate) { item in
                    let net = item.income - item.expenses
                    VStack(spacing: 4) {
                        Text(item.month)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text((net >= 0 ? "+" : "") + CurrencyFormatter.shared.format(net))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(net >= 0 ? .green : .red)
                        Text("net")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    private struct BalancePoint: Identifiable {
        let id: Date
        let balance: Double
    }

    private var balancePoints: [BalancePoint] {
        let sorted = allTransactions.sorted { $0.date < $1.date }
        let initial = accounts.reduce(Decimal.zero) { $0 + $1.initialBalance }
        var running = initial
        return sorted.map { txn in
            running += txn.amount
            return BalancePoint(id: txn.date, balance: Double(truncating: running as NSDecimalNumber))
        }
    }

    private var balanceChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            let points = balancePoints
            let currentBalance = points.last?.balance ?? Double(truncating: accounts.reduce(Decimal.zero) { $0 + $1.initialBalance } as NSDecimalNumber)
            let minBal = points.min(by: { $0.balance < $1.balance })
            let maxBal = points.max(by: { $0.balance < $1.balance })

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance Over Time")
                        .font(.headline)
                    Text("Current: \(CurrencyFormatter.shared.format(Decimal(currentBalance)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppTheme.accent(for: scheme))
                }
                Spacer()
                if let minBal, let maxBal, points.count > 1 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(shortCurrency(maxBal.balance), systemImage: "arrow.up")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Label(shortCurrency(minBal.balance), systemImage: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.id),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(AppTheme.accent(for: scheme))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", point.id),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accent(for: scheme).opacity(0.3), AppTheme.accent(for: scheme).opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(shortCurrency(v))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    private struct CategoryData: Identifiable {
        let id: String
        let name: String
        let total: Decimal
        let pct: Double
        let txnCount: Int
        let merchants: [MerchantData]
    }

    private struct MerchantData: Identifiable {
        let id: String
        let name: String
        let total: Decimal
        let pct: Double
        let txnCount: Int
    }

    private var categoryData: [CategoryData] {
        let expenses = allTransactions.filter { $0.isExpense }
        let grouped = Dictionary(grouping: expenses) { $0.category?.name ?? "Uncategorized" }
        let totalExp = expenses.reduce(Decimal.zero) { $0 + abs($1.amount) }
        return grouped.map { key, txns in
            let total = txns.reduce(Decimal.zero) { $0 + abs($1.amount) }
            let pct = totalExp > 0 ? Double(truncating: (total / totalExp * 100) as NSDecimalNumber) : 0
            let merchantGrouped = Dictionary(grouping: txns) { $0.title }
            let merchants = merchantGrouped.map { mName, mTxns in
                let mTotal = mTxns.reduce(Decimal.zero) { $0 + abs($1.amount) }
                let mPct = total > 0 ? Double(truncating: (mTotal / total * 100) as NSDecimalNumber) : 0
                return MerchantData(id: mName, name: mName, total: mTotal, pct: mPct, txnCount: mTxns.count)
            }.sorted { $0.total > $1.total }
            return CategoryData(id: key, name: key, total: total, pct: pct, txnCount: txns.count, merchants: merchants)
        }
        .sorted { $0.total > $1.total }
    }

    private struct MerchantSlice: Identifiable {
        let id: String
        let name: String
        let amount: Double
        let category: String
    }

    private var categoryBreakdown: some View {
        let data = categoryData
        let totalExp = data.reduce(Decimal.zero) { $0 + $1.total }
        let selectedItem = selectedCategory.flatMap { sel in data.first { $0.name == sel } }

        let merchantSlices: [MerchantSlice] = selectedItem.map { item in
            item.merchants.map { m in
                MerchantSlice(id: m.id, name: m.name, amount: Double(truncating: m.total as NSDecimalNumber), category: item.name)
            }
        } ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Spending by Category")
                    .font(.headline)
                Spacer()
                if selectedCategory != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { selectedCategory = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption2)
                            Text("All Categories")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.accent(for: scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)

            ZStack {
                if let selected = selectedItem {
                    Chart(merchantSlices) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amount),
                            innerRadius: .ratio(0.6),
                            outerRadius: .ratio(0.92),
                            angularInset: 1.0
                        )
                        .foregroundStyle(by: .value("Merchant", slice.name))
                        .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 280)

                    VStack(spacing: 6) {
                        Text(selected.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(CurrencyFormatter.shared.format(selected.total))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(AppTheme.accent(for: scheme))
                        Text(String(format: "%.1f%% of total", selected.pct))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(selected.txnCount) transactions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 140)
                } else {
                    Chart(data) { item in
                        SectorMark(
                            angle: .value("Amount", Double(truncating: item.total as NSDecimalNumber)),
                            innerRadius: .ratio(0.6),
                            outerRadius: .ratio(0.92),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", item.name))
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 280)

                    VStack(spacing: 6) {
                        Text("Total Spending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(totalExp))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(data.count) categories")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 140)
                }
            }

            Divider()
                .padding(.top, 20)
                .padding(.bottom, 16)

            if let selected = selectedItem {
                ForEach(selected.merchants) { merchant in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(AppTheme.accent(for: scheme).opacity(0.6))
                            .frame(width: 6, height: 6)

                        Text(merchant.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.accent(for: scheme).opacity(0.3))
                                .frame(width: geo.size.width * min(merchant.pct / 100.0, 1.0))
                        }
                        .frame(width: 80, height: 6)

                        Text(String(format: "%.0f%%", merchant.pct))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)

                        Text(CurrencyFormatter.shared.format(merchant.total))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            } else {
                ForEach(data.prefix(12)) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedCategory = item.name
                        }
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.accent(for: scheme))
                                .frame(width: 4, height: 22)

                            Text(item.name)
                                .font(.subheadline)
                            Spacer()

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AppTheme.accent(for: scheme).opacity(0.25))
                                    .frame(width: geo.size.width * min(item.pct / 100.0, 1.0))
                            }
                            .frame(width: 80, height: 6)

                            Text(String(format: "%.0f%%", item.pct))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 35, alignment: .trailing)

                            Text(CurrencyFormatter.shared.format(item.total))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .trailing)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    private func shortCurrency(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "$%.0fK", value / 1000)
        }
        return String(format: "$%.0f", value)
    }
}
