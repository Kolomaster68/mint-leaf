import Foundation

struct SpendingAnomaly: Identifiable {
    let id = UUID()
    let category: String
    let currentAmount: Decimal
    let averageAmount: Decimal
    let percentChange: Double
    let period: String
}

final class AnomalyDetector {
    static func detect(transactions: [Transaction], months: Int = 3) -> [SpendingAnomaly] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let lookbackStart = calendar.date(byAdding: .month, value: -months, to: currentMonthStart) ?? now

        let currentMonth = transactions.filter { $0.isExpense && $0.date >= currentMonthStart }
        let historical = transactions.filter { $0.isExpense && $0.date >= lookbackStart && $0.date < currentMonthStart }

        let currentByCategory = Dictionary(grouping: currentMonth) { $0.category?.name ?? "Uncategorized" }
        let historicalByCategory = Dictionary(grouping: historical) { $0.category?.name ?? "Uncategorized" }

        var anomalies: [SpendingAnomaly] = []

        for (category, currentTxns) in currentByCategory {
            let currentTotal = currentTxns.reduce(Decimal.zero) { $0 + abs($1.amount) }
            let histTxns = historicalByCategory[category] ?? []
            guard !histTxns.isEmpty else { continue }

            let histTotal = histTxns.reduce(Decimal.zero) { $0 + abs($1.amount) }
            let monthlyAvg = histTotal / Decimal(months)
            guard monthlyAvg > 0 else { continue }

            let change = Double(truncating: ((currentTotal - monthlyAvg) / monthlyAvg * 100) as NSDecimalNumber)

            if abs(change) >= 30 {
                anomalies.append(SpendingAnomaly(
                    category: category,
                    currentAmount: currentTotal,
                    averageAmount: monthlyAvg,
                    percentChange: change,
                    period: "this month"
                ))
            }
        }

        return anomalies.sorted { abs($0.percentChange) > abs($1.percentChange) }
    }
}
