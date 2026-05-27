import Foundation
import SwiftData

enum ScheduledTransactionProcessor {
    @MainActor
    static func processOverdue(context: ModelContext) {
        let now = Date()
        let calendar = Calendar.current

        let descriptor = FetchDescriptor<ScheduledTransaction>(
            predicate: #Predicate { $0.isActive && $0.nextDate <= now },
            sortBy: [SortDescriptor(\.nextDate)]
        )

        guard let overdue = try? context.fetch(descriptor) else { return }

        for scheduled in overdue {
            // PHASE 1: If nextDate is more than 60 days old, jump forward mathematically.
            // No transactions created for ancient dates — just skip ahead.
            let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: now) ?? now
            if scheduled.nextDate < sixtyDaysAgo {
                scheduled.nextDate = jumpForward(from: scheduled.nextDate, to: sixtyDaysAgo, frequency: scheduled.frequency, calendar: calendar)
            }

            // PHASE 2: Process recent overdue dates (last 60 days to now).
            // Create at most a few transactions for genuinely missed charges.
            var safetyCount = 0
            while scheduled.nextDate <= now && scheduled.isActive && safetyCount < 10 {
                safetyCount += 1

                if let endDate = scheduled.endDate, scheduled.nextDate > endDate {
                    scheduled.isActive = false
                    break
                }

                // Only charge if there's a linked account and no duplicate
                if let account = scheduled.account {
                    let txnDate = scheduled.nextDate
                    let alreadyExists = scheduled.generatedTransactions.contains { txn in
                        calendar.isDate(txn.date, inSameDayAs: txnDate)
                    }

                    if !alreadyExists {
                        let transaction = Transaction(
                            amount: scheduled.amount,
                            title: scheduled.title,
                            date: txnDate,
                            notes: "Auto-charged: \(scheduled.frequency.rawValue)",
                            category: scheduled.category,
                            account: account
                        )
                        transaction.scheduledSource = scheduled
                        context.insert(transaction)
                        account.adjustBalance(by: scheduled.amount)
                    }
                }

                let next = nextOccurrence(after: scheduled.nextDate, frequency: scheduled.frequency, calendar: calendar)
                if next <= scheduled.nextDate {
                    scheduled.nextDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                    break
                }
                scheduled.nextDate = next
            }

            // If still stuck, force to tomorrow
            if scheduled.nextDate <= now {
                scheduled.nextDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            }

            try? context.save()
        }
    }

    /// Mathematically jump from an old date to near the target date,
    /// preserving the correct cycle alignment. O(1), no looping.
    private static func jumpForward(from start: Date, to target: Date, frequency: RecurrenceFrequency, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.day, .weekOfYear, .month, .year], from: start, to: target)

        switch frequency {
        case .daily:
            let days = max(components.day ?? 0, 0)
            return calendar.date(byAdding: .day, value: days, to: start) ?? target

        case .weekly:
            let weeks = max(components.weekOfYear ?? 0, 0)
            return calendar.date(byAdding: .weekOfYear, value: weeks, to: start) ?? target

        case .biweekly:
            let weeks = max(components.weekOfYear ?? 0, 0)
            let biweeks = (weeks / 2) * 2
            return calendar.date(byAdding: .weekOfYear, value: biweeks, to: start) ?? target

        case .monthly:
            let months = max(components.month ?? 0, 0)
            return calendar.date(byAdding: .month, value: months, to: start) ?? target

        case .quarterly:
            let months = max(components.month ?? 0, 0)
            let quarters = (months / 3) * 3
            return calendar.date(byAdding: .month, value: quarters, to: start) ?? target

        case .yearly:
            let years = max(components.year ?? 0, 0)
            return calendar.date(byAdding: .year, value: years, to: start) ?? target
        }
    }

    private static func nextOccurrence(after date: Date, frequency: RecurrenceFrequency, calendar: Calendar) -> Date {
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
