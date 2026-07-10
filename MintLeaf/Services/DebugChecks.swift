#if DEBUG
import Foundation
import SwiftData

/// Tiny launch-time self-checks for the money math — the app has no test target,
/// so these asserts are the tripwire if statement-cycle or recurrence logic breaks.
/// Runs only in DEBUG builds, against a throwaway in-memory store.
enum DebugChecks {
    @MainActor
    static func run() {
        do { try checkStatementBoundary() } catch { assertionFailure("DebugChecks store setup failed: \(error)") }
        checkRecurrenceAdvance()
    }

    /// A transaction stamped exactly midnight the day after the statement date must
    /// count as unbilled, not billed — and never both (the v4.0 double-count bug).
    @MainActor
    private static func checkStatementBoundary() throws {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self,
                             BudgetItem.self, ScheduledTransaction.self, CategoryRule.self,
                             MerchantAlias.self, Goal.self, Tag.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext

        let card = Account(name: "Check Card", type: .creditCard)
        card.statementDay = 15
        ctx.insert(card)

        guard let statement = card.lastStatementDate() else {
            assertionFailure("lastStatementDate returned nil for configured card")
            return
        }
        let cal = Calendar.current

        // Spend inside the closed cycle → billed.
        let inCycle = Transaction(amount: -100, title: "in cycle",
                                  date: cal.date(byAdding: .day, value: -5, to: statement)!,
                                  account: card)
        // Spend at exactly midnight the day after the statement → unbilled.
        let boundary = Transaction(amount: -50, title: "boundary",
                                   date: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: statement))!,
                                   account: card)
        ctx.insert(inCycle)
        ctx.insert(boundary)

        assert(card.statementBalance == 100,
               "statementBalance should be 100, got \(card.statementBalance) — boundary txn leaked into the bill")
        assert(card.unbilledBalance == 50,
               "unbilledBalance should be 50, got \(card.unbilledBalance)")
    }

    /// advance() must strictly increase for every frequency, or the scheduled
    /// processor's catch-up loop can spin.
    private static func checkRecurrenceAdvance() {
        let date = Date()
        for freq in RecurrenceFrequency.allCases {
            assert(freq.advance(date) > date, "advance() did not move \(freq.rawValue) forward")
        }
    }
}
#endif
