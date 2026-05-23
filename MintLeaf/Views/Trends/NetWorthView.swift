import SwiftUI
import SwiftData
import Charts

struct NetWorthView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var timeRange: TimeRange = .sixMonths

    enum TimeRange: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"

        var days: Int {
            switch self {
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .all: return 9999
            }
        }
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var assets: Decimal {
        activeAccounts.filter { $0.currentBalance > 0 }.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    private var liabilities: Decimal {
        activeAccounts.filter { $0.currentBalance < 0 }.reduce(Decimal.zero) { $0 + abs($1.currentBalance) }
    }

    private var netWorth: Decimal {
        activeAccounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                netWorthHeader
                netWorthChart
                accountBreakdown
                assetLiabilityBreakdown
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Net Worth")
    }

    // MARK: - Header

    private var netWorthHeader: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Total Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.shared.format(netWorth))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(netWorth >= 0 ? AppTheme.accent(for: scheme) : .red)
            }

            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text("Assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(assets))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 32)
                VStack(spacing: 4) {
                    Text("Liabilities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(liabilities))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Chart

    private struct NetWorthPoint: Identifiable {
        let id: Date
        let netWorth: Double
        let assets: Double
        let liabilities: Double
    }

    private var netWorthPoints: [NetWorthPoint] {
        let allTxns = activeAccounts.flatMap { $0.transactions }.sorted { $0.date < $1.date }
        guard !allTxns.isEmpty else { return [] }

        let calendar = Calendar.current
        let cutoff: Date
        if timeRange == .all {
            cutoff = allTxns.first?.date ?? Date()
        } else {
            cutoff = calendar.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        }

        // Build running balance per account
        var accountBalances: [Account: Decimal] = [:]
        for account in activeAccounts {
            accountBalances[account] = account.initialBalance
        }

        var points: [NetWorthPoint] = []
        var lastDay: Date?

        let filteredTxns = allTxns // process all but only emit points after cutoff
        for txn in filteredTxns {
            guard let acct = txn.account else { continue }
            accountBalances[acct, default: .zero] += txn.amount

            let day = calendar.startOfDay(for: txn.date)
            guard day >= cutoff else { lastDay = day; continue }

            if let last = lastDay, last == day {
                // Update existing point for same day
                if !points.isEmpty {
                    points[points.count - 1] = makePoint(day: day, balances: accountBalances)
                }
            } else {
                points.append(makePoint(day: day, balances: accountBalances))
            }
            lastDay = day
        }

        return points
    }

    private func makePoint(day: Date, balances: [Account: Decimal]) -> NetWorthPoint {
        var totalAssets: Decimal = 0
        var totalLiabilities: Decimal = 0
        for (_, bal) in balances {
            if bal > 0 { totalAssets += bal }
            else { totalLiabilities += abs(bal) }
        }
        let net = totalAssets - totalLiabilities
        return NetWorthPoint(
            id: day,
            netWorth: Double(truncating: net as NSDecimalNumber),
            assets: Double(truncating: totalAssets as NSDecimalNumber),
            liabilities: Double(truncating: totalLiabilities as NSDecimalNumber)
        )
    }

    private var netWorthChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Net Worth Over Time")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            if netWorthPoints.count > 1 {
                Chart {
                    ForEach(netWorthPoints) { point in
                        LineMark(
                            x: .value("Date", point.id),
                            y: .value("Net Worth", point.netWorth)
                        )
                        .foregroundStyle(AppTheme.accent(for: scheme))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        AreaMark(
                            x: .value("Date", point.id),
                            yStart: .value("Baseline", 0),
                            yEnd: .value("Net Worth", point.netWorth)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent(for: scheme).opacity(0.2), AppTheme.accent(for: scheme).opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
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
            } else {
                Text("Not enough data to show a chart yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    private func shortCurrency(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "\(CurrencyFormatter.shared.symbol)%.1fK", value / 1000)
        }
        return String(format: "\(CurrencyFormatter.shared.symbol)%.0f", value)
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        let balanceColor: Color = account.currentBalance >= 0 ? .primary : .red
        let iconColor: Color = account.currentBalance >= 0 ? AppTheme.accent(for: scheme) : .red
        HStack(spacing: 12) {
            Image(systemName: account.icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                Text(account.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatter.shared.format(account.currentBalance))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(balanceColor)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Account Breakdown

    private var sortedAccounts: [Account] {
        activeAccounts.sorted(by: { $0.currentBalance > $1.currentBalance })
    }

    private var accountBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts")
                .font(.headline)

            ForEach(Array(sortedAccounts), id: \.id) { (account: Account) in
                accountRow(account)
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Asset/Liability Breakdown

    private var assetLiabilityBreakdown: some View {
        HStack(spacing: 16) {
            // Assets column
            assetBreakdownCard

            // Liabilities column
            liabilityBreakdownCard
        }
    }

    private var assetAccounts: [Account] {
        activeAccounts.filter { $0.currentBalance > 0 }.sorted(by: { $0.currentBalance > $1.currentBalance })
    }

    private var liabilityAccountsList: [Account] {
        activeAccounts.filter { $0.currentBalance < 0 }.sorted(by: { $0.currentBalance < $1.currentBalance })
    }

    private var assetBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assets", systemImage: "arrow.up.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            if assetAccounts.isEmpty {
                Text("No assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assetAccounts, id: \.id) { account in
                    HStack {
                        Text(account.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(account.currentBalance))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var liabilityBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Liabilities", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            if liabilityAccountsList.isEmpty {
                Text("No liabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(liabilityAccountsList, id: \.id) { account in
                    HStack {
                        Text(account.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(abs(account.currentBalance)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
