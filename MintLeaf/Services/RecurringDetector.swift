import Foundation

struct RecurringPattern: Identifiable {
    let id = UUID()
    let merchantName: String
    let averageAmount: Decimal
    let frequency: DetectedFrequency
    let confidence: Double
    let lastDate: Date
    let nextExpectedDate: Date
    let occurrences: Int
}

enum DetectedFrequency: String {
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    case irregular = "Irregular"

    var approximateDays: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        case .quarterly: return 91
        case .yearly: return 365
        case .irregular: return 0
        }
    }
}

final class RecurringDetector {
    static func detect(transactions: [Transaction]) -> [RecurringPattern] {
        let grouped = Dictionary(grouping: transactions.filter { $0.isExpense }) {
            $0.title.lowercased()
        }

        var patterns: [RecurringPattern] = []

        for (merchant, txns) in grouped {
            guard txns.count >= 3 else { continue }
            let sorted = txns.sorted { $0.date < $1.date }
            let intervals = zip(sorted, sorted.dropFirst()).map {
                Calendar.current.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0
            }
            guard !intervals.isEmpty else { continue }

            let avgInterval = Double(intervals.reduce(0, +)) / Double(intervals.count)
            let variance = intervals.map { pow(Double($0) - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)
            let stdDev = sqrt(variance)

            let (frequency, confidence) = classifyFrequency(avgInterval: avgInterval, stdDev: stdDev)
            guard confidence >= 0.5 else { continue }

            let avgAmount = sorted.reduce(Decimal.zero) { $0 + abs($1.amount) } / Decimal(sorted.count)
            let lastDate = sorted.last!.date
            let nextDate = Calendar.current.date(byAdding: .day, value: frequency.approximateDays, to: lastDate) ?? lastDate

            patterns.append(RecurringPattern(
                merchantName: sorted.last!.title,
                averageAmount: avgAmount,
                frequency: frequency,
                confidence: confidence,
                lastDate: lastDate,
                nextExpectedDate: nextDate,
                occurrences: sorted.count
            ))
        }

        return patterns.sorted { $0.confidence > $1.confidence }
    }

    private static func classifyFrequency(avgInterval: Double, stdDev: Double) -> (DetectedFrequency, Double) {
        let candidates: [(DetectedFrequency, Double)] = [
            (.weekly, 7),
            (.biweekly, 14),
            (.monthly, 30),
            (.quarterly, 91),
            (.yearly, 365),
        ]

        var best: (DetectedFrequency, Double) = (.irregular, 0)
        for (freq, expected) in candidates {
            let diff = abs(avgInterval - expected)
            let tolerance = expected * 0.25
            if diff <= tolerance {
                let confidence = max(0, 1.0 - (diff / tolerance)) * max(0, 1.0 - (stdDev / expected))
                if confidence > best.1 {
                    best = (freq, confidence)
                }
            }
        }
        return best
    }
}
