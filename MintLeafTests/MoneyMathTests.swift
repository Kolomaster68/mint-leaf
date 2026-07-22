import XCTest
import SwiftData
@testable import MintLeaf

/// Locks down the money-critical paths: balance recalculation, transfer pairing,
/// credit-card statement boundaries, backup round-trips, recurrence, and FX.
/// These replace the old DEBUG-only launch asserts with real, CI-runnable tests.
@MainActor
final class MoneyMathTests: XCTestCase {

    /// Reuses the host app's single in-memory container (a second container traps
    /// SwiftData), wiped clean so each test starts from empty.
    private func makeContext() throws -> ModelContext {
        let ctx = try XCTUnwrap(MintLeafApp.testContainer, "host app didn't publish a test container").mainContext
        for acc in try ctx.fetch(FetchDescriptor<Account>()) { ctx.delete(acc) }
        for t in try ctx.fetch(FetchDescriptor<Transaction>()) { ctx.delete(t) }
        for c in try ctx.fetch(FetchDescriptor<MintLeaf.Category>()) { ctx.delete(c) }
        for b in try ctx.fetch(FetchDescriptor<Budget>()) { ctx.delete(b) }
        for i in try ctx.fetch(FetchDescriptor<BudgetItem>()) { ctx.delete(i) }
        for s in try ctx.fetch(FetchDescriptor<ScheduledTransaction>()) { ctx.delete(s) }
        for r in try ctx.fetch(FetchDescriptor<CategoryRule>()) { ctx.delete(r) }
        for m in try ctx.fetch(FetchDescriptor<MerchantAlias>()) { ctx.delete(m) }
        for g in try ctx.fetch(FetchDescriptor<Goal>()) { ctx.delete(g) }
        for tag in try ctx.fetch(FetchDescriptor<Tag>()) { ctx.delete(tag) }
        try ctx.save()
        return ctx
    }

    // MARK: Balance

    func testRecalculateBalanceEqualsOpeningPlusTransactions() throws {
        let ctx = try makeContext()
        let acct = Account(name: "Current", type: .checking, initialBalance: 100)
        ctx.insert(acct)
        for amt in [Decimal(50), -30, -12.5] {
            ctx.insert(Transaction(amount: amt, title: "t", account: acct))
        }
        acct.recalculateBalance()
        XCTAssertEqual(acct.currentBalance, Decimal(107.5)) // 100 + 50 - 30 - 12.5
    }

    // MARK: Transfers

    func testDeletingOneSideOfTransferRemovesBothAndReversesBalances() throws {
        let ctx = try makeContext()
        let source = Account(name: "A", type: .checking, initialBalance: 500)
        let dest = Account(name: "B", type: .savings, initialBalance: 0)
        ctx.insert(source); ctx.insert(dest)

        let pid = UUID()
        let out = Transaction(amount: -100, title: "Transfer", account: source)
        out.transferDestination = dest
        out.transferPairID = pid
        let mirror = Transaction(amount: 100, title: "Transfer", account: dest)
        mirror.transferDestination = source
        mirror.transferPairID = pid
        ctx.insert(out); ctx.insert(mirror)
        source.adjustBalance(by: -100) // 400
        dest.adjustBalance(by: 100)    // 100

        TransferService.delete(out, context: ctx)
        try ctx.save()

        XCTAssertEqual(source.currentBalance, 500, "source not reversed")
        XCTAssertEqual(dest.currentBalance, 0, "mirror not reversed")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Transaction>()).isEmpty, "both sides of the transfer should be deleted")
    }

    // MARK: Credit-card statement boundary (the v4.0 double-count bug)

    func testStatementBoundaryChargeIsUnbilledNotBilled() throws {
        let ctx = try makeContext()
        let card = Account(name: "Card", type: .creditCard)
        card.statementDay = 15
        ctx.insert(card)

        let statement = try XCTUnwrap(card.lastStatementDate())
        let cal = Calendar.current
        ctx.insert(Transaction(amount: -100, title: "in cycle",
                               date: cal.date(byAdding: .day, value: -5, to: statement)!, account: card))
        ctx.insert(Transaction(amount: -50, title: "boundary",
                               date: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: statement))!, account: card))

        XCTAssertEqual(card.statementBalance, 100, "boundary charge leaked into the bill")
        XCTAssertEqual(card.unbilledBalance, 50)
    }

    // MARK: Recurrence

    func testRecurrenceAdvanceAlwaysMovesForward() {
        let now = Date()
        for freq in RecurrenceFrequency.allCases {
            XCTAssertGreaterThan(freq.advance(now), now, "\(freq.rawValue) did not advance")
        }
    }

    // MARK: Backup round-trip

    func testBackupExportRestoreReproducesTree() throws {
        let ctx = try makeContext()
        let acct = Account(name: "Main", type: .checking, initialBalance: 200)
        ctx.insert(acct)
        ctx.insert(Transaction(amount: -25, title: "coffee", account: acct))
        ctx.insert(Transaction(amount: 1000, title: "pay", account: acct))
        acct.recalculateBalance()
        try ctx.save()

        let data = try BackupManager.export(context: ctx)
        let summary = try BackupManager.restore(from: data, context: ctx)

        XCTAssertEqual(summary.accounts, 1)
        XCTAssertEqual(summary.transactions, 2)
        let restored = try ctx.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.currentBalance, 1175) // 200 - 25 + 1000
    }

    // MARK: FX

    func testFXConvertSameCurrencyIsIdentityAndCrossIsPositive() {
        let fx = ExchangeRateService.shared
        XCTAssertEqual(fx.convert(100, from: "USD", to: "USD"), 100)
        XCTAssertGreaterThan(fx.convert(100, from: "USD", to: "GBP"), 0)
    }
}
