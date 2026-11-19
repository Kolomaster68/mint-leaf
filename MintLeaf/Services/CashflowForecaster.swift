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

        // Auto-posted scheduled charges are projected explicitly below; leaving them in
        // the running average counted every bill and subscription twice.
        let recent = transactions.filter { $0.date >= lookback && $0.scheduledSource == nil }
        let dayCount = max(1, calendar.dateComponents([.day], from: lookback, to: now).day ?? 90)

        let totalSpend = recent.filter { $0.isExpense }.reduce(Decimal.zero) { $0 + abs($1.amount) }
        let totalIncome = recent.filter { $0.isIncome }.reduce(Decimal.zero) { $0 + $1.amount }
        let avgDailySpend = totalSpend / Decimal(dayCount)
        let avgDailyIncome = totalIncome / Decimal(dayCount)
        let netDaily = avgDailyIncome - avgDailySpend

        var points: [ForecastPoint] = []

        // Every occurrence inside the horizon, not just the next one — a monthly bill
        // lands six times in a six-month forecast.
        let horizon = calendar.date(byAdding: .day, value: days, to: now) ?? now
        var scheduledByDay: [Date: Decimal] = [:]
        for scheduled in scheduledTransactions where scheduled.isActive {
            var occurrence = scheduled.nextDate
            var guardCount = 0
            while occurrence <= horizon && guardCount < 400 {
                if let end = scheduled.endDate, occurrence > end { break }
                scheduledByDay[calendar.startOfDay(for: occurrence), default: 0] += scheduled.convertedAmount
                let next = scheduled.advance(occurrence)
                guard next > occurrence else { break }
                occurrence = next
                guardCount += 1
            }
        }

        var projected = currentBalance
        var daysUntilNegative: Int?

        for dayOffset in 0...days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            if dayOffset > 0 {
                projected += netDaily + (scheduledByDay[calendar.startOfDay(for: date)] ?? 0)
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
        // Day 30 itself — this used to be the end of the horizon, so a 90-day forecast
        // showed its 90-day figure under a "30 days" label.
        let balance30d = points[min(30, points.count - 1)].projectedBalance

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

// MARK: - Left until payday

extension CashflowForecaster {
    struct Payday {
        let left: Decimal       // day-to-day money after the bills below
        let bills: Decimal      // outgoing schedules due before payday
        let payday: Date?       // next scheduled income; nil = counting to month end
    }

    /// Current + cash balances minus every outgoing schedule due before the next scheduled
    /// income (or month end if there's none). Savings, cards and loans are left out:
    /// a subscription on a credit card doesn't leave the current account today.
    static func untilPayday(accounts: [Account], scheduled: [ScheduledTransaction], now: Date = Date()) -> Payday {
        let spending = accounts.filter { !$0.isArchived && ($0.type == .checking || $0.type == .cash) }
        let ids = Set(spending.map(\.id))
        let cash = spending.reduce(Decimal.zero) { $0 + $1.convertedBalance }
        let active = scheduled.filter(\.isActive)
        let payday = active.filter { $0.amount > 0 && $0.nextDate > now }.map(\.nextDate).min()
        let end = payday ?? Calendar.current.dateInterval(of: .month, for: now)?.end ?? now

        var bills = Decimal.zero
        for s in active where s.amount < 0 && (s.account.map { ids.contains($0.id) } ?? true) {
            var date = s.nextDate
            var guardCount = 0
            while date < end && guardCount < 100 {
                if let stop = s.endDate, date > stop { break }
                bills -= s.convertedAmount
                let next = s.advance(date)
                guard next > date else { break }
                date = next
                guardCount += 1
            }
        }
        return Payday(left: cash - bills, bills: bills, payday: payday)
    }
}
