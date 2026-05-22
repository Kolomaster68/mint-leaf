import Foundation
import SwiftData

enum ScheduledTransactionProcessor {
    /// Process all overdue scheduled transactions on app launch.
    /// Creates transactions on the linked account and advances nextDate.
    @MainActor
    static func processOverdue(context: ModelContext) {
        let now = Date()

        let descriptor = FetchDescriptor<ScheduledTransaction>(
            predicate: #Predicate { $0.isActive && $0.nextDate <= now },
            sortBy: [SortDescriptor(\.nextDate)]
        )

        guard let overdue = try? context.fetch(descriptor) else { return }

        for scheduled in overdue {
            // Process all missed occurrences (in case app wasn't opened for a while)
            while scheduled.nextDate <= now && scheduled.isActive {
                // Check end date
                if let endDate = scheduled.endDate, scheduled.nextDate > endDate {
                    scheduled.isActive = false
                    break
                }

                // Create the transaction on the linked account
                if let account = scheduled.account {
                    let transaction = Transaction(
                        amount: scheduled.amount,
                        title: scheduled.title,
                        date: scheduled.nextDate,
                        notes: "Auto-charged from scheduled: \(scheduled.frequency.rawValue)",
                        category: scheduled.category,
                        account: account
                    )
                    transaction.scheduledSource = scheduled
                    context.insert(transaction)
                }

                // Advance to next occurrence
                scheduled.nextDate = nextOccurrence(after: scheduled.nextDate, frequency: scheduled.frequency)
            }
        }

        try? context.save()
    }

    private static func nextOccurrence(after date: Date, frequency: RecurrenceFrequency) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}
