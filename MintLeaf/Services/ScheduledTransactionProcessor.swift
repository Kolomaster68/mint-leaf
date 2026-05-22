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
            // Safety: cap iterations to prevent infinite loops from bad data
            var iterations = 0
            let maxIterations = 1000

            while scheduled.nextDate <= now && scheduled.isActive && iterations < maxIterations {
                iterations += 1

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
                let previous = scheduled.nextDate
                let next = nextOccurrence(after: previous, frequency: scheduled.frequency)

                // If date didn't actually advance, break to prevent infinite loop
                if next <= previous {
                    scheduled.nextDate = now
                    break
                }

                scheduled.nextDate = next
            }

            // If we hit the cap, just jump to now so it doesn't loop again next launch
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
