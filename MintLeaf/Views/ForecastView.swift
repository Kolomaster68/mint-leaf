import SwiftUI
import SwiftData
import Charts

struct ForecastView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \ScheduledTransaction.nextDate) private var scheduled: [ScheduledTransaction]

    @State private var forecastDays: Int = 90

    private var allTransactions: [Transaction] {
        accounts.flatMap { $0.transactions }
    }

    private var totalBalance: Decimal {
        accounts.filter { !$0.isArchived }.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                forecastChart
                upcomingScheduled
                cashflowProjection
                scenarioCards
            }
            .padding(20)
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Forecast")
    }

    // MARK: - Forecast Chart

    private var forecast: CashflowForecast {
        CashflowForecaster.forecast(
            currentBalance: totalBalance,
            transactions: allTransactions,
            scheduledTransactions: scheduled,
            days: forecastDays
        )
    }

    private var forecastChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Balance Forecast")
                        .font(.headline)
                    Text("Current: \(CurrencyFormatter.shared.format(totalBalance))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppTheme.accent(for: scheme))
                }

                Spacer()

                Picker("Period", selection: $forecastDays) {
                    Text("30d").tag(30)
                    Text("60d").tag(60)
                    Text("90d").tag(90)
                    Text("6M").tag(180)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            // Key metrics
            HStack(spacing: 12) {
                metricCard(
                    "Projected",
                    value: forecast.projectedBalance30d,
                    subtitle: "30 days",
                    color: forecast.projectedBalance30d >= 0 ? .green : .red
                )
                metricCard(
                    "Daily Spend",
                    value: forecast.averageDailySpend,
                    subtitle: "average",
                    color: .red,
                    prefix: "-"
                )
                metricCard(
                    "Daily Income",
                    value: forecast.averageDailyIncome,
                    subtitle: "average",
                    color: .green,
                    prefix: "+"
                )
            }

            // Warning
            if let danger = forecast.daysUntilNegative {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Balance could go negative in **\(danger) days** at current pace")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            // Chart
            let points = forecast.points
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", Double(truncating: point.projectedBalance as NSDecimalNumber))
                )
                .foregroundStyle(point.isHistorical ? AppTheme.accent(for: scheme) : AppTheme.accent(for: scheme).opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: point.isHistorical ? [] : [5, 3]))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", 0),
                    yEnd: .value("Balance", Double(truncating: point.projectedBalance as NSDecimalNumber))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.accent(for: scheme).opacity(0.15), AppTheme.accent(for: scheme).opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
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
    }

    private func metricCard(_ title: String, value: Decimal, subtitle: String, color: Color, prefix: String = "") -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(prefix)\(CurrencyFormatter.shared.format(value))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Upcoming Scheduled

    private var upcomingScheduled: some View {
        let upcoming = scheduled
            .filter { $0.isActive }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(10)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Scheduled")
                .font(.headline)

            if upcoming.isEmpty {
                Text("No scheduled transactions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(upcoming)) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isSubscription ? "arrow.triangle.2.circlepath" : "calendar")
                            .foregroundStyle(item.nextDate < Date() ? .red : AppTheme.accent(for: scheme))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                            HStack(spacing: 4) {
                                Text(item.nextDate, style: .date)
                                if item.nextDate < Date() {
                                    Text("Overdue")
                                        .foregroundStyle(.red)
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(CurrencyFormatter.shared.format(item.amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(item.amount < 0 ? .red : .green)
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Cashflow Projection

    private var cashflowProjection: some View {
        let activeSubs = scheduled.filter { $0.isActive }
        let monthlyOut = activeSubs.filter { $0.amount < 0 }.reduce(Decimal.zero) { $0 + abs($1.monthlyEquivalent) }
        let monthlyIn = activeSubs.filter { $0.amount > 0 }.reduce(Decimal.zero) { $0 + $1.monthlyEquivalent }
        let netMonthly = monthlyIn - monthlyOut

        return VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Commitment")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Incoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+\(CurrencyFormatter.shared.format(monthlyIn))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Outgoing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(CurrencyFormatter.shared.format(monthlyOut))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(netMonthly))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(netMonthly >= 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Scenarios

    private var scenarioCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What-If Scenarios")
                .font(.headline)

            let netDaily = forecast.averageDailyIncome - forecast.averageDailySpend
            let monthsUntilZero: Int? = netDaily < 0 ? Int(truncating: (totalBalance / abs(netDaily)) as NSDecimalNumber) / 30 : nil

            HStack(spacing: 12) {
                scenarioCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "If you save 10% more",
                    value: CurrencyFormatter.shared.format(forecast.projectedBalance30d + (forecast.averageDailySpend * 3)),
                    subtitle: "30-day balance",
                    color: .green
                )
                scenarioCard(
                    icon: "exclamationmark.triangle",
                    title: monthsUntilZero != nil ? "Runway" : "Sustainable",
                    value: monthsUntilZero != nil ? "\(monthsUntilZero!) months" : "Positive trend",
                    subtitle: monthsUntilZero != nil ? "until balance hits zero" : "at current pace",
                    color: monthsUntilZero != nil ? .orange : .green
                )
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent(for: scheme).opacity(0.12), lineWidth: 1))
    }

    private func scenarioCard(icon: String, title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func shortCurrency(_ value: Double) -> String {
        let symbol = CurrencyFormatter.shared.symbol
        if abs(value) >= 1000 {
            return String(format: "\(symbol)%.1fK", value / 1000)
        }
        return String(format: "\(symbol)%.0f", value)
    }
}
