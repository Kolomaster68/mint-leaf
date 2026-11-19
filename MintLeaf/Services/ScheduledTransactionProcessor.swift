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
            // Older schedules predate anchorDay: pin it to where they are now so they stop drifting.
            if scheduled.anchorDay == nil {
                scheduled.anchorDay = calendar.component(.day, from: scheduled.nextDate)
            }
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

                    // Schedule and account can differ in currency (a $ subscription on a £ card).
                    let amount = ExchangeRateService.shared.convert(scheduled.amount, from: scheduled.currency, to: account.currency)
                    // The real payment may already be here (entered or imported). Adopt it
                    // rather than posting a second copy — this is what doubled the rent.
                    let real = alreadyExists ? nil : account.transactions.first { txn in
                        txn.scheduledSource == nil && txn.amount == amount &&
                        abs(calendar.dateComponents([.day], from: txnDate, to: txn.date).day ?? 999) <= 5
                    }
                    if let real {
                        real.scheduledSource = scheduled
                    } else if !alreadyExists {
                        let transaction = Transaction(
                            amount: amount,
                            title: scheduled.title,
                            date: txnDate,
                            notes: "\(autoNote): \(scheduled.frequency.rawValue)",
                            category: scheduled.category,
                            account: account
                        )
                        transaction.scheduledSource = scheduled
                        context.insert(transaction)
                        account.adjustBalance(by: amount)
                    }
                }

                let next = scheduled.advance(scheduled.nextDate)
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

            context.saveOrLog()
        }
    }

    // MARK: Cancelled-subscription detection

    /// Prefix on charges the app posted itself. A bank import that matches one clears
    /// it (DuplicateDetector), so a charge still carrying it was never seen at the bank.
    static let autoNote = "Auto-charged"

    static func isUnconfirmed(_ txn: Transaction) -> Bool { txn.notes.hasPrefix(autoNote) }

    /// The trailing run of charges the bank never showed.
    static func ghostCharges(of scheduled: ScheduledTransaction) -> [Transaction] {
        Array(scheduled.generatedTransactions.sorted { $0.date > $1.date }.prefix { isUnconfirmed($0) })
    }

    /// Outgoing schedules whose last two charges never appeared in the bank data that has
    /// since been imported — the subscription was most likely cancelled (the Uber One ghost).
    /// Accounts that are only typed in by hand never trip this: there's no bank data to miss.
    static func likelyCancelled(_ scheduled: [ScheduledTransaction]) -> [ScheduledTransaction] {
        scheduled.filter { s in
            guard s.isActive, s.amount < 0, let account = s.account else { return false }
            let ghosts = ghostCharges(of: s)
            guard ghosts.count >= 2, let latest = ghosts.first?.date,
                  let covered = Calendar.current.date(byAdding: .day, value: 5, to: latest) else { return false }
            return account.transactions.contains { $0.scheduledSource == nil && $0.date > covered }
        }
    }

    /// Stops the schedule and removes the charges that never really happened.
    @MainActor
    static func stop(_ scheduled: ScheduledTransaction, context: ModelContext) {
        scheduled.isActive = false
        for ghost in ghostCharges(of: scheduled) {
            ghost.account?.adjustBalance(by: -ghost.amount)
            context.delete(ghost)
        }
        context.saveOrLog()
    }

    /// The user says it's still live (price change, paid elsewhere): accept the charges.
    static func keep(_ scheduled: ScheduledTransaction) {
        for ghost in ghostCharges(of: scheduled) { ghost.notes = "" }
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

}
