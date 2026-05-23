import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var reportType: ReportType = .monthly
    @State private var selectedMonth: Date = Date()
    @State private var showingExporter = false
    @State private var csvContent = ""

    enum ReportType: String, CaseIterable {
        case monthly = "Monthly"
        case yearly = "Yearly"
    }

    private var allTransactions: [Transaction] {
        accounts.flatMap { $0.transactions }
    }

    private var filteredTransactions: [Transaction] {
        let calendar = Calendar.current
        return allTransactions.filter { txn in
            switch reportType {
            case .monthly:
                return calendar.isDate(txn.date, equalTo: selectedMonth, toGranularity: .month)
            case .yearly:
                return calendar.isDate(txn.date, equalTo: selectedMonth, toGranularity: .year)
            }
        }
    }

    private var income: Decimal {
        filteredTransactions.filter { $0.amount > 0 && !$0.isTransfer }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var expenses: Decimal {
        filteredTransactions.filter { $0.amount < 0 && !$0.isTransfer }.reduce(Decimal.zero) { $0 + abs($1.amount) }
    }

    private var net: Decimal { income - expenses }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                controlsBar
                summaryCards
                categoryBreakdown
                topMerchants
                accountSummary
                exportButton
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Reports")
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvContent),
            contentType: .commaSeparatedText,
            defaultFilename: reportFilename
        ) { _ in }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack {
            Picker("Type", selection: $reportType) {
                ForEach(ReportType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            HStack(spacing: 8) {
                Button { stepDate(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                Text(dateLabel)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 120)
                Button { stepDate(1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        switch reportType {
        case .monthly:
            f.dateFormat = "MMMM yyyy"
        case .yearly:
            f.dateFormat = "yyyy"
        }
        return f.string(from: selectedMonth)
    }

    private func stepDate(_ direction: Int) {
        let calendar = Calendar.current
        switch reportType {
        case .monthly:
            selectedMonth = calendar.date(byAdding: .month, value: direction, to: selectedMonth) ?? selectedMonth
        case .yearly:
            selectedMonth = calendar.date(byAdding: .year, value: direction, to: selectedMonth) ?? selectedMonth
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            reportCard("Income", value: income, color: .green, icon: "arrow.down.circle.fill")
            reportCard("Expenses", value: expenses, color: .red, icon: "arrow.up.circle.fill")
            reportCard("Net", value: net, color: net >= 0 ? .green : .red, icon: net >= 0 ? "plus.circle.fill" : "minus.circle.fill")
        }
    }

    private func reportCard(_ title: String, value: Decimal, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.shared.format(value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Category Breakdown

    private struct CategorySpend: Identifiable {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let amount: Decimal
        let percentage: Double
    }

    private var categoryData: [CategorySpend] {
        let expenseTxns = filteredTransactions.filter { $0.amount < 0 && !$0.isTransfer }
        let total = expenseTxns.reduce(Decimal.zero) { $0 + abs($1.amount) }
        guard total > 0 else { return [] }

        var grouped: [String: (name: String, icon: String, colorHex: String, amount: Decimal)] = [:]
        for txn in expenseTxns {
            let catName = txn.category?.name ?? "Uncategorised"
            let icon = txn.category?.icon ?? "questionmark.circle"
            let color = txn.category?.colorHex ?? "888888"
            let key = catName
            grouped[key, default: (catName, icon, color, .zero)].amount += abs(txn.amount)
        }

        return grouped.map { (key, val) in
            CategorySpend(
                id: key,
                name: val.name,
                icon: val.icon,
                colorHex: val.colorHex,
                amount: val.amount,
                percentage: Double(truncating: (val.amount / total * 100) as NSDecimalNumber)
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending by Category")
                .font(.headline)

            let data = categoryData
            if data.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Pie chart
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", Double(truncating: item.amount as NSDecimalNumber)),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.colorHex))
                    .cornerRadius(4)
                }
                .frame(height: 200)

                // Legend
                ForEach(data) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: item.colorHex))
                            .frame(width: 10, height: 10)
                        Image(systemName: item.icon)
                            .font(.caption)
                            .foregroundStyle(Color(hex: item.colorHex))
                            .frame(width: 20)
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f%%", item.percentage))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(item.amount))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Top Merchants

    private var topMerchantData: [(key: String, amount: Decimal, count: Int)] {
        let expenseTxns = filteredTransactions.filter { $0.amount < 0 && !$0.isTransfer }
        var merchantTotals: [String: (amount: Decimal, count: Int)] = [:]
        for txn in expenseTxns {
            let key = txn.title
            merchantTotals[key, default: (.zero, 0)].amount += abs(txn.amount)
            merchantTotals[key, default: (.zero, 0)].count += 1
        }
        return merchantTotals
            .sorted { $0.value.amount > $1.value.amount }
            .prefix(10)
            .map { (key: $0.key, amount: $0.value.amount, count: $0.value.count) }
    }

    private var topMerchants: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(.headline)

            let merchants = topMerchantData
            if merchants.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(merchants.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.key)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(entry.count) transaction\(entry.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.shared.format(entry.amount))
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Account Summary

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account Activity")
                .font(.headline)

            ForEach(accounts.filter { !$0.isArchived }) { account in
                let txns = filteredTransactions.filter { $0.account?.id == account.id }
                let accountIncome = txns.filter { $0.amount > 0 && !$0.isTransfer }.reduce(Decimal.zero) { $0 + $1.amount }
                let accountExpenses = txns.filter { $0.amount < 0 && !$0.isTransfer }.reduce(Decimal.zero) { $0 + abs($1.amount) }

                HStack(spacing: 12) {
                    Image(systemName: account.icon)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent(for: scheme))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(txns.count) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(CurrencyFormatter.shared.format(accountIncome))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                        Text("-\(CurrencyFormatter.shared.format(accountExpenses))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Export

    private var reportFilename: String {
        let f = DateFormatter()
        switch reportType {
        case .monthly: f.dateFormat = "yyyy-MM"
        case .yearly: f.dateFormat = "yyyy"
        }
        return "MintLeaf-Report-\(f.string(from: selectedMonth)).csv"
    }

    private var exportButton: some View {
        Button {
            csvContent = buildReport()
            showingExporter = true
        } label: {
            Label("Export Report as CSV", systemImage: "arrow.down.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent(for: scheme))
        .disabled(filteredTransactions.isEmpty)
    }

    private func buildReport() -> String {
        var lines = ["Date,Account,Payee,Amount,Category,Notes"]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for txn in filteredTransactions.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: txn.date)
            let acct = csvEscape(txn.account?.name ?? "")
            let payee = csvEscape(txn.title)
            let amount = "\(txn.amount)"
            let category = csvEscape(txn.category?.name ?? "")
            let notes = csvEscape(txn.notes)
            lines.append("\(date),\(acct),\(payee),\(amount),\(category),\(notes)")
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
