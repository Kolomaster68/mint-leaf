import Foundation
import SwiftData

enum ScheduledTransactionProcessor {
    /// Process all overdue scheduled transactions on app launch.
    /// Creates transactions on the linked account and advances nextDate.
    /// Only creates transactions for the most recent missed occurrence —
    /// older ones are skipped silently to avoid flooding the account.
    @MainActor
    static func processOverdue(context: ModelContext) {
        let now = Date()
        // Only create transactions for dates within the last 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now

        let descriptor = FetchDescriptor<ScheduledTransaction>(
            predicate: #Predicate { $0.isActive && $0.nextDate <= now },
            sortBy: [SortDescriptor(\.nextDate)]
        )

        guard let overdue = try? context.fetch(descriptor) else { return }

        for scheduled in overdue {
            var iterations = 0
            let maxIterations = 100

            while scheduled.nextDate <= now && scheduled.isActive && iterations < maxIterations {
                iterations += 1

                // Check end date
                if let endDate = scheduled.endDate, scheduled.nextDate > endDate {
                    scheduled.isActive = false
                    break
                }

                // Only create a transaction if the date is recent (within 30 days)
                // Older dates just get skipped — we advance past them silently
                if scheduled.nextDate >= cutoff, let account = scheduled.account {
                    let transaction = Transaction(
                        amount: scheduled.amount,
                        title: scheduled.title,
                        date: scheduled.nextDate,
                        notes: "Auto-charged: \(scheduled.frequency.rawValue)",
                        category: scheduled.category,
                        account: account
                    )
                    transaction.scheduledSource = scheduled
                    context.insert(transaction)
                }

                // Advance to next occurrence
                let previous = scheduled.nextDate
                let next = nextOccurrence(after: previous, frequency: scheduled.frequency)

                if next <= previous {
                    scheduled.nextDate = now
                    break
                }

                scheduled.nextDate = next
            }

            if iterations >= maxIterations {
                scheduled.nextDate = now
            }
        }

        try? context.save()
    }

    private static func nextOccurrence(after date: Date, frequency: RecurrenceFrequency) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date.addingTimeInterval(604800)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date.addingTimeInterval(1209600)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(2592000)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date.addingTimeInterval(7776000)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date.addingTimeInterval(31536000)
        }
    }
}
