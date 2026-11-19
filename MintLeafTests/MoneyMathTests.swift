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

    // MARK: Regressions from the November audit

    /// Paying last month's bill inside this cycle must not cancel this month's spending.
    func testStatementBalanceSurvivesPreviousStatementPayment() throws {
        let ctx = try makeContext()
        let card = Account(name: "Card", type: .creditCard, initialBalance: -160)
        card.statementDay = 15
        ctx.insert(card)
        let statement = try XCTUnwrap(card.lastStatementDate())
        let cal = Calendar.current
        ctx.insert(Transaction(amount: 160, title: "payment", date: cal.date(byAdding: .day, value: -10, to: statement)!, account: card))
        ctx.insert(Transaction(amount: -168, title: "spend", date: cal.date(byAdding: .day, value: -5, to: statement)!, account: card))
        XCTAssertEqual(card.statementBalance, 168)
        XCTAssertFalse(card.statementSettled)
        ctx.insert(Transaction(amount: 168, title: "payment", date: cal.date(byAdding: .day, value: 1, to: statement)!, account: card))
        XCTAssertTrue(card.statementSettled)
    }

    func testStatementDueDateCanBeOverdue() throws {
        let card = Account(name: "Card", type: .creditCard)
        card.statementDay = 15
        card.paymentDueOffsetDays = 1
        let cal = Calendar.current
        let ref = cal.date(from: DateComponents(year: 2026, month: 6, day: 25))!
        let due = try XCTUnwrap(card.statementDueDate(asOf: ref))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: due), DateComponents(month: 6, day: 16))
        XCTAssertLessThan(due, ref, "a missed due date must stay in the past, not jump to next month")
    }

    func testBudgetRollsOverToCurrentPeriod() {
        let cal = Calendar.current
        let budget = Budget(name: "b", period: .monthly, startDate: cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!)
        let window = budget.currentPeriod(at: cal.date(from: DateComponents(year: 2026, month: 4, day: 10))!)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: window.start), DateComponents(month: 3, day: 31))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: window.end), DateComponents(month: 4, day: 30))
    }

    func testUserInputAmountsParseWholeStringOrNothing() {
        XCTAssertEqual(Decimal(userInput: "1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(Decimal(userInput: "£45"), 45)
        XCTAssertEqual(Decimal(userInput: "(12.50)"), Decimal(string: "-12.5"))
        XCTAssertNil(Decimal(userInput: "12.50abc"))
        XCTAssertNil(Decimal(userInput: ""))
    }

    func testQIFDatesAreDayFirstWhenTheFileSaysSo() throws {
        let lines = ["D05/03/2026", "D25/03/2026"]
        XCTAssertTrue(QIFParser.isDayFirst(lines))
        let d = try XCTUnwrap(QIFParser.parseDate("05/03/26", dayFirst: true))
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: d), DateComponents(year: 2026, month: 3, day: 5))
    }

    func testDuplicateMatchingIsOneToOne() {
        let day = Date()
        var pool = [Transaction(amount: -6.2, title: "TFL", date: day)]
        XCTAssertTrue(DuplicateDetector.consumeDuplicate(of: Transaction(amount: -6.2, title: "TFL", date: day), in: &pool))
        XCTAssertFalse(DuplicateDetector.consumeDuplicate(of: Transaction(amount: -6.2, title: "TFL", date: day), in: &pool),
                       "a second identical fare is a real second journey")
    }

    func testScheduledChargeAdoptsExistingPaymentInsteadOfDoubling() throws {
        let ctx = try makeContext()
        let acct = Account(name: "A", type: .checking, currency: "GBP", initialBalance: 500)
        ctx.insert(acct)
        let due = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let rent = ScheduledTransaction(amount: -150, title: "Rent", nextDate: due, account: acct, currency: "GBP")
        ctx.insert(rent)
        ctx.insert(Transaction(amount: -150, title: "Mum", date: Date(), account: acct))
        acct.recalculateBalance()
        try ctx.save()
        ScheduledTransactionProcessor.processOverdue(context: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Transaction>()).count, 1)
        XCTAssertEqual(acct.currentBalance, 350)
    }

    func testForecastProjectsEveryRecurrence() {
        let weekly = ScheduledTransaction(amount: -10, title: "w", frequency: .weekly,
                                          nextDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                                          currency: ExchangeRateService.shared.preferredCurrency)
        let f = CashflowForecaster.forecast(currentBalance: 100, transactions: [], scheduledTransactions: [weekly], days: 30)
        XCTAssertEqual(f.projectedBalance30d, 50) // days 1, 8, 15, 22, 29
    }

    func testMonthlyScheduleOnThe31stDoesNotDriftAfterShortMonths() {
        let cal = Calendar.current
        let rent = ScheduledTransaction(amount: -500, title: "Rent", nextDate: cal.date(from: DateComponents(year: 2027, month: 1, day: 31))!)
        let feb = rent.advance(rent.nextDate)
        let mar = rent.advance(feb)
        XCTAssertEqual(cal.component(.day, from: feb), 28)
        XCTAssertEqual(cal.component(.day, from: mar), 31, "rent drifted to the 28th")
    }

    // MARK: Upgrades (payday, rollover, cancelled subscriptions)

    func testLeftUntilPaydaySubtractsBillsDueBeforeIncome() throws {
        let ctx = try makeContext()
        let gbp = ExchangeRateService.shared.preferredCurrency
        let current = Account(name: "Current", type: .checking, currency: gbp, initialBalance: 400)
        let card = Account(name: "Card", type: .creditCard, currency: gbp, initialBalance: 0)
        ctx.insert(current); ctx.insert(card)
        current.recalculateBalance(); card.recalculateBalance()
        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: n, to: Date())! }
        let pay = ScheduledTransaction(amount: 900, title: "Pay", nextDate: day(10), account: current, currency: gbp)
        let phone = ScheduledTransaction(amount: -20, title: "Phone", frequency: .weekly, nextDate: day(2), account: current, currency: gbp)
        let netflix = ScheduledTransaction(amount: -11, title: "Netflix", nextDate: day(3), account: card, currency: gbp)
        let late = ScheduledTransaction(amount: -300, title: "After payday", nextDate: day(12), account: current, currency: gbp)
        [pay, phone, netflix, late].forEach(ctx.insert)
        let p = CashflowForecaster.untilPayday(accounts: [current, card], scheduled: [pay, phone, netflix, late])
        XCTAssertEqual(p.bills, 40, "phone on days 2 and 9 only; card bill and post-payday bill excluded")
        XCTAssertEqual(p.left, 360)
    }

    func testBudgetRolloverCarriesUnspentAndOverspend() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        let food = MintLeaf.Category(name: "Food")
        ctx.insert(food)
        let start = cal.date(byAdding: .month, value: -2, to: cal.startOfDay(for: Date()))!
        let budget = Budget(name: "b", period: .monthly, startDate: start)
        budget.rollover = true
        ctx.insert(budget)
        let item = BudgetItem(amount: 100, category: food, budget: budget)
        ctx.insert(item)
        // Two past months: spent 70 then 150 → carried 100*2 - 220 = -20
        for (offset, amt) in [(0, -70), (1, -150)] {
            let d = cal.date(byAdding: .day, value: 3, to: cal.date(byAdding: .month, value: offset, to: start)!)!
            ctx.insert(Transaction(amount: Decimal(amt), title: "shop", date: d, category: food))
        }
        try ctx.save()
        XCTAssertEqual(item.carriedOver, -20)
        XCTAssertEqual(item.available, 80)
        budget.rollover = false
        XCTAssertEqual(item.available, 100)
    }

    func testGhostSubscriptionIsFlaggedOnlyOnceBankDataCoversIt() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        let acct = Account(name: "A", type: .checking, currency: "GBP", initialBalance: 100)
        ctx.insert(acct)
        let uber = ScheduledTransaction(amount: -5, title: "Uber One", nextDate: cal.date(byAdding: .day, value: 20, to: Date())!, account: acct, currency: "GBP")
        ctx.insert(uber)
        for months in [-2, -1] {
            let t = Transaction(amount: -5, title: "Uber One", date: cal.date(byAdding: .month, value: months, to: Date())!,
                                notes: "\(ScheduledTransactionProcessor.autoNote): Monthly", account: acct)
            t.scheduledSource = uber
            ctx.insert(t)
        }
        try ctx.save()
        XCTAssertTrue(ScheduledTransactionProcessor.likelyCancelled([uber]).isEmpty, "no bank data yet — can't tell")

        ctx.insert(Transaction(amount: -3, title: "Tesco", date: Date(), account: acct))
        acct.recalculateBalance()
        try ctx.save()
        XCTAssertEqual(ScheduledTransactionProcessor.likelyCancelled([uber]).count, 1)

        ScheduledTransactionProcessor.stop(uber, context: ctx)
        XCTAssertFalse(uber.isActive)
        XCTAssertEqual(acct.currentBalance, 97, "ghost charges removed, real spend kept")
    }

    func testImportMatchingAPlaceholderConfirmsIt() {
        let placeholder = Transaction(amount: -5, title: "Uber One", date: Date(), notes: "Auto-charged: Monthly")
        placeholder.scheduledSource = ScheduledTransaction(amount: -5, title: "Uber One", nextDate: Date())
        var pool = [placeholder]
        XCTAssertTrue(DuplicateDetector.consumeDuplicate(of: Transaction(amount: -5, title: "UBER *ONE", date: Date()), in: &pool))
        XCTAssertFalse(ScheduledTransactionProcessor.isUnconfirmed(placeholder))
    }
}

