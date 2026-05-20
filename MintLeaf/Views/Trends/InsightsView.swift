import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]

    private var allTransactions: [Transaction] {
        accounts.flatMap { $0.transactions }
    }

    private var totalBalance: Decimal {
        accounts.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                forecastSection
                anomalySection
                recurringSection
            }
            .padding()
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Insights")
    }

    private var forecastSection: some View {
        let forecast = CashflowForecaster.forecast(
            currentBalance: totalBalance,
            transactions: allTransactions,
            scheduledTransactions: scheduled
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("Cashflow Forecast")
                .font(.headline)

            HStack(spacing: 16) {
                ForecastCard(
                    title: "7-Day",
                    amount: forecast.projectedBalance7d,
                    subtitle: "projected"
                )
                ForecastCard(
                    title: "30-Day",
                    amount: forecast.projectedBalance30d,
                    subtitle: "projected"
                )
                VStack(alignment: .leading) {
                    Text("Daily Avg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(CurrencyFormatter.shared.format(forecast.averageDailySpend))")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text("+\(CurrencyFormatter.shared.format(forecast.averageDailyIncome))")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
            }

            if let danger = forecast.daysUntilNegative {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Balance could go negative in \(danger) days at current pace")
                        .font(.subheadline)
                }
                .padding()
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            Chart(forecast.points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", Double(truncating: point.projectedBalance as NSDecimalNumber))
                )
                .foregroundStyle(point.isHistorical ? AppTheme.accent(for: scheme) : AppTheme.accent(for: scheme).opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", Double(truncating: point.projectedBalance as NSDecimalNumber))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accent(for: scheme).opacity(0.2), AppTheme.accent(for: scheme).opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(AppTheme.accent(for: scheme).opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v >= 1000 ? String(format: "$%.0fK", v / 1000) : String(format: "$%.0f", v))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    private var anomalySection: some View {
        let anomalies = AnomalyDetector.detect(transactions: allTransactions)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Spending Alerts")
                .font(.headline)

            if anomalies.isEmpty {
                Text("No unusual spending detected this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(anomalies) { anomaly in
                    HStack {
                        Image(systemName: anomaly.percentChange > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(anomaly.percentChange > 0 ? .red : .green)
                        VStack(alignment: .leading) {
                            Text(anomaly.category)
                                .font(.subheadline.bold())
                            Text("\(CurrencyFormatter.shared.format(anomaly.currentAmount)) \(anomaly.period) vs \(CurrencyFormatter.shared.format(anomaly.averageAmount)) avg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%+.0f%%", anomaly.percentChange))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(anomaly.percentChange > 0 ? .red : .green)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder
    private var recurringSection: some View {
        let patterns = RecurringDetector.detect(transactions: allTransactions)
        let subs = scheduled.filter { $0.isSubscription && $0.isActive }

        if !patterns.isEmpty || !subs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Detected Subscriptions & Recurring")
                    .font(.headline)

                if !subs.isEmpty {
                    ForEach(subs.sorted(by: { $0.monthlyEquivalent > $1.monthlyEquivalent })) { sub in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(sub.title)
                                    .font(.subheadline)
                                HStack(spacing: 4) {
                                    Text(sub.frequency.rawValue)
                                    Text("·")
                                    Text("Subscription")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(CurrencyFormatter.shared.format(abs(sub.amount)))
                                    .font(.subheadline.monospacedDigit())
                                Text("Next: \(sub.nextDate, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }

                ForEach(patterns.prefix(10)) { pattern in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pattern.merchantName)
                                .font(.subheadline)
                            HStack(spacing: 4) {
                                Text(pattern.frequency.rawValue)
                                Text("·")
                                Text("\(pattern.occurrences) occurrences")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(CurrencyFormatter.shared.format(pattern.averageAmount))
                                .font(.subheadline.monospacedDigit())
                            Text("Next: \(pattern.nextExpectedDate, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
    }
}

struct ForecastCard: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let amount: Decimal
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.shared.format(amount))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(amount >= 0 ? Color.primary : .red)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }
}
