import Foundation

struct ForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let projectedBalance: Decimal
    let isHistorical: Bool
}

struct CashflowForecast {
    let points: [ForecastPoint]
    let projectedBalance7d: Decimal
    let projectedBalance30d: Decimal
    let averageDailySpend: Decimal
    let averageDailyIncome: Decimal
    let daysUntilNegative: Int?
}

final class CashflowForecaster {
    static func forecast(
        currentBalance: Decimal,
        transactions: [Transaction],
        scheduledTransactions: [ScheduledTransaction],
        days: Int = 30
    ) -> CashflowForecast {
        let calendar = Calendar.current
        let now = Date()
        let lookback = calendar.date(byAdding: .day, value: -90, to: now) ?? now

        let recent = transactions.filter { $0.date >= lookback }
        let dayCount = max(1, calendar.dateComponents([.day], from: lookback, to: now).day ?? 90)

        let totalSpend = recent.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
        let totalIncome = recent.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
        let avgDailySpend = totalSpend / Decimal(dayCount)
        let avgDailyIncome = totalIncome / Decimal(dayCount)
        let netDaily = avgDailyIncome - avgDailySpend

        var points: [ForecastPoint] = []

        var projected = currentBalance
        var daysUntilNegative: Int?

        for dayOffset in 0...days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            if dayOffset > 0 {
                var dayAmount = netDaily

                for scheduled in scheduledTransactions where scheduled.isActive {
                    let scheduledDay = calendar.startOfDay(for: scheduled.nextDate)
                    let forecastDay = calendar.startOfDay(for: date)
                    if scheduledDay == forecastDay {
                        dayAmount += scheduled.amount
                    }
                }

                projected += dayAmount
            }

            points.append(ForecastPoint(
                date: date,
                projectedBalance: projected,
                isHistorical: dayOffset == 0
            ))

            if projected < 0 && daysUntilNegative == nil && dayOffset > 0 {
                daysUntilNegative = dayOffset
            }
        }

        let balance7d = points.first { calendar.dateComponents([.day], from: now, to: $0.date).day == 7 }?.projectedBalance ?? projected
        let balance30d = points.last?.projectedBalance ?? projected

        return CashflowForecast(
            points: points,
            projectedBalance7d: balance7d,
            projectedBalance30d: balance30d,
            averageDailySpend: avgDailySpend,
            averageDailyIncome: avgDailyIncome,
            daysUntilNegative: daysUntilNegative
        )
    }
}
