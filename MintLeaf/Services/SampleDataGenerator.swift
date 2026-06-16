import Foundation
import SwiftData

struct SampleDataGenerator {
    static func populate(context: ModelContext) {
        let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if !existingAccounts.isEmpty { return }

        // Reset currency to match sample data
        UserDefaults.standard.set("USD", forKey: "defaultCurrency")

        var categories = fetchCategories(context: context)
        if categories.isEmpty {
            DefaultCategories.seed(context: context)
            try? context.save()
            categories = fetchCategories(context: context)
        }
        let cal = Calendar.current

        let checking = Account(name: "Chase Checking", type: .checking, currency: "USD", initialBalance: 3200, icon: "building.columns", colorHex: "#2196F3", sortOrder: 0)
        let savings = Account(name: "Marcus Savings", type: .savings, currency: "USD", initialBalance: 18500, icon: "banknote", colorHex: "#4CAF50", sortOrder: 1)
        let creditCard = Account(name: "Amex Gold", type: .creditCard, currency: "USD", initialBalance: 0, icon: "creditcard", colorHex: "#FF9800", sortOrder: 2)
        let cash = Account(name: "Cash Wallet", type: .cash, currency: "USD", initialBalance: 340, icon: "dollarsign.circle", colorHex: "#9C27B0", sortOrder: 3)

        // Demonstrate the credit card billing cycle: statement on the 15th,
        // payment due 21 days later, paid from Chase Checking.
        creditCard.statementDay = 15
        creditCard.paymentDueOffsetDays = 21
        creditCard.paymentSourceAccountID = checking.id
        creditCard.purchaseAPR = 22.9 // so the "pay in full" interest estimate appears
        // Give the funding account an arranged overdraft so funds warnings are realistic.
        checking.overdraftLimit = 500
        checking.overdraftEAR = 39.9
        checking.unarrangedOverdraftFee = 20

        context.insert(checking)
        context.insert(savings)
        context.insert(creditCard)
        context.insert(cash)

        let cat = { (name: String) -> Category? in
            categories.first { $0.name == name }
        }

        struct TxnTemplate {
            let title: String
            let amountRange: ClosedRange<Double>
            let category: String
            let isIncome: Bool

            init(_ title: String, _ range: ClosedRange<Double>, _ category: String, isIncome: Bool = false) {
                self.title = title
                self.amountRange = range
                self.category = category
                self.isIncome = isIncome
            }
        }

        let checkingExpenses: [TxnTemplate] = [
            TxnTemplate("Whole Foods", 35...95, "Groceries"),
            TxnTemplate("Trader Joe's", 25...65, "Groceries"),
            TxnTemplate("Kroger", 30...80, "Groceries"),
            TxnTemplate("Chevron", 45...75, "Gas & Fuel"),
            TxnTemplate("Shell", 40...70, "Gas & Fuel"),
            TxnTemplate("Netflix", 15.99...15.99, "Subscriptions"),
            TxnTemplate("Spotify", 10.99...10.99, "Subscriptions"),
            TxnTemplate("Rent Payment", 1650...1650, "Housing"),
            TxnTemplate("Con Edison", 85...140, "Utilities"),
            TxnTemplate("Water Utility", 45...45, "Utilities"),
            TxnTemplate("T-Mobile", 55...55, "Utilities"),
            TxnTemplate("Xfinity Internet", 65...65, "Utilities"),
            TxnTemplate("Chipotle", 12...18, "Food & Dining"),
            TxnTemplate("Chick-fil-A", 8...15, "Food & Dining"),
            TxnTemplate("Starbucks", 4.50...7.50, "Food & Dining"),
            TxnTemplate("Panera Bread", 10...16, "Food & Dining"),
            TxnTemplate("Amazon", 8...120, "Shopping"),
            TxnTemplate("Target", 15...90, "Clothing"),
            TxnTemplate("Metro Transit", 2.50...5.50, "Transportation"),
            TxnTemplate("Uber", 10...30, "Transportation"),
            TxnTemplate("CVS Pharmacy", 8...35, "Healthcare"),
            TxnTemplate("AMC Theatres", 14...22, "Entertainment"),
            TxnTemplate("Walgreens", 5...20, "Other"),
        ]

        let creditCardExpenses: [TxnTemplate] = [
            TxnTemplate("Amazon Prime", 14.99...14.99, "Subscriptions"),
            TxnTemplate("Apple iCloud", 2.99...2.99, "Subscriptions"),
            TxnTemplate("Nordstrom", 40...220, "Shopping"),
            TxnTemplate("DoorDash", 18...40, "Food & Dining"),
            TxnTemplate("Delta Airlines", 120...350, "Travel"),
            TxnTemplate("Marriott Hotels", 150...300, "Travel"),
            TxnTemplate("H&M", 20...90, "Clothing"),
            TxnTemplate("Planet Fitness", 24.99...24.99, "Healthcare"),
            TxnTemplate("Barnes & Noble", 10...25, "Education"),
        ]

        for monthsAgo in 0..<6 {
            let monthDate = cal.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()

            let salary = Transaction(
                amount: 4800,
                title: "Monthly Salary",
                date: firstWeekday(of: monthDate, weekday: 5, calendar: cal),
                category: cat("Salary"),
                account: checking
            )
            context.insert(salary)

            if monthsAgo % 2 == 0 {
                let freelance = Transaction(
                    amount: Decimal(Double.random(in: 250...800).rounded(to: 2)),
                    title: "Freelance Invoice",
                    date: randomDay(in: monthDate, calendar: cal),
                    category: cat("Freelance"),
                    account: checking
                )
                context.insert(freelance)
            }

            let expenseCount = Int.random(in: 12...18)
            for _ in 0..<expenseCount {
                let template = checkingExpenses.randomElement()!
                let amount = -Decimal(Double.random(in: template.amountRange).rounded(to: 2))
                let txn = Transaction(
                    amount: amount,
                    title: template.title,
                    date: randomDay(in: monthDate, calendar: cal),
                    category: cat(template.category),
                    account: checking
                )
                txn.isReconciled = monthsAgo > 1
                context.insert(txn)
            }

            let ccCount = Int.random(in: 4...8)
            for _ in 0..<ccCount {
                let template = creditCardExpenses.randomElement()!
                let amount = -Decimal(Double.random(in: template.amountRange).rounded(to: 2))
                let txn = Transaction(
                    amount: amount,
                    title: template.title,
                    date: randomDay(in: monthDate, calendar: cal),
                    category: cat(template.category),
                    account: creditCard
                )
                txn.isReconciled = monthsAgo > 1
                context.insert(txn)
            }

            if monthsAgo < 3 {
                let cashCount = Int.random(in: 2...5)
                for _ in 0..<cashCount {
                    let titles = ["Bodega", "Farmers Market", "Sports Bar", "Yellow Cab", "Yard Sale"]
                    let cats = ["Groceries", "Food & Dining", "Entertainment", "Transportation", "Shopping"]
                    let idx = Int.random(in: 0..<titles.count)
                    let txn = Transaction(
                        amount: -Decimal(Double.random(in: 3...30).rounded(to: 2)),
                        title: titles[idx],
                        date: randomDay(in: monthDate, calendar: cal),
                        category: cat(cats[idx]),
                        account: cash
                    )
                    context.insert(txn)
                }
            }
        }

        let interest = Transaction(
            amount: 32.50,
            title: "Monthly Interest",
            date: cal.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
            category: cat("Interest"),
            account: savings
        )
        context.insert(interest)

        let budget = Budget(name: "May Budget", period: .monthly, startDate: cal.date(from: DateComponents(year: 2026, month: 5, day: 1)) ?? Date())
        context.insert(budget)

        let budgetCategories: [(String, Decimal)] = [
            ("Groceries", 300),
            ("Food & Dining", 150),
            ("Transportation", 100),
            ("Entertainment", 80),
            ("Shopping", 200),
            ("Subscriptions", 60),
            ("Utilities", 250),
        ]
        for (catName, amount) in budgetCategories {
            let item = BudgetItem(amount: amount, category: cat(catName), budget: budget)
            context.insert(item)
        }

        let scheduledItems: [(String, Double, String, RecurrenceFrequency, Int, Bool)] = [
            ("Rent Payment", -1650, "Housing", .monthly, 1, false),
            ("Car Payment", -385, "Transportation", .monthly, 5, false),
            ("Netflix", -15.99, "Subscriptions", .monthly, 12, true),
            ("Spotify", -10.99, "Subscriptions", .monthly, 15, true),
            ("iCloud+", -2.99, "Subscriptions", .monthly, 8, true),
            ("ChatGPT Plus", -20.00, "Subscriptions", .monthly, 3, true),
            ("YouTube Premium", -13.99, "Subscriptions", .monthly, 18, true),
            ("Planet Fitness", -24.99, "Healthcare", .monthly, 1, true),
            ("State Farm Insurance", -145, "Insurance", .monthly, 20, false),
            ("Monthly Salary", 4800, "Salary", .monthly, 28, false),
        ]
        for (title, amount, catName, freq, dayOfMonth, isSub) in scheduledItems {
            var nextComponents = cal.dateComponents([.year, .month], from: Date())
            nextComponents.day = dayOfMonth
            var nextDate = cal.date(from: nextComponents) ?? Date()
            if nextDate < Date() {
                nextDate = cal.date(byAdding: .month, value: 1, to: nextDate) ?? nextDate
            }
            let scheduled = ScheduledTransaction(
                amount: Decimal(amount),
                title: title,
                frequency: freq,
                nextDate: nextDate,
                account: checking,
                category: cat(catName),
                isSubscription: isSub
            )
            context.insert(scheduled)
        }

        let uncategorizedItems: [(String, Double, Account)] = [
            ("PYMT VENMO 8294", -42.00, checking),
            ("SQ *COFFEE SHOP NYC", -6.75, checking),
            ("TRANSFER FROM SAVINGS", 500.00, checking),
            ("POS DEBIT COSTCO GAS", -52.30, checking),
            ("ACH WITHDRAWAL INSURANCE", -89.00, checking),
            ("ZELLE PAYMENT JOHN D", -25.00, checking),
            ("APPLE.COM/BILL", -9.99, creditCard),
            ("TST* SUSHI PLACE", -34.50, creditCard),
            ("AMZN MKTP US*2K4L9", -27.83, creditCard),
            ("LYFT *RIDE", -18.40, creditCard),
            ("WM SUPERCENTER", -63.12, checking),
            ("PP*EBAY PURCHASE", -15.99, creditCard),
        ]
        for (title, amount, account) in uncategorizedItems {
            let txn = Transaction(
                amount: Decimal(amount),
                title: title,
                date: randomDay(in: Date(), calendar: cal),
                category: nil,
                account: account
            )
            context.insert(txn)
        }

        // MARK: - Tags
        // Remove any existing tags first to avoid duplicates on re-run
        let existingTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        for old in existingTags { context.delete(old) }

        let tagBusiness = Tag(name: "Business", colorHex: "2196F3", sortOrder: 0)
        let tagHoliday = Tag(name: "Holiday", colorHex: "FF9800", sortOrder: 1)
        let tagTaxDeductible = Tag(name: "Tax Deductible", colorHex: "4CAF50", sortOrder: 2)
        let tagEssential = Tag(name: "Essential", colorHex: "E91E63", sortOrder: 3)
        let tagSplurge = Tag(name: "Splurge", colorHex: "9C27B0", sortOrder: 4)

        context.insert(tagBusiness)
        context.insert(tagHoliday)
        context.insert(tagTaxDeductible)
        context.insert(tagEssential)
        context.insert(tagSplurge)

        // Tag existing transactions — match broadly so every tag has entries
        let allTxns = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        for txn in allTxns {
            let title = txn.title.lowercased()
            // Business: salary, freelance, and work-adjacent
            if title.contains("freelance") || title.contains("salary") || title.contains("amazon prime") || title.contains("icloud") {
                txn.tags.append(tagBusiness)
            }
            // Holiday: travel + dining out + entertainment
            if title.contains("delta") || title.contains("marriott") || title.contains("doordash") || title.contains("amc") {
                txn.tags.append(tagHoliday)
            }
            // Tax Deductible: housing, utilities, insurance, internet
            if title.contains("rent") || title.contains("insurance") || title.contains("internet") || title.contains("con edison") || title.contains("water utility") || title.contains("t-mobile") {
                txn.tags.append(tagTaxDeductible)
            }
            // Essential: groceries, utilities, transport, healthcare
            if title.contains("whole foods") || title.contains("trader") || title.contains("kroger") || title.contains("chevron") || title.contains("shell") || title.contains("metro transit") || title.contains("cvs") || title.contains("walgreens") || title.contains("planet fitness") {
                txn.tags.append(tagEssential)
            }
            // Splurge: shopping, dining, entertainment, fashion
            if title.contains("nordstrom") || title.contains("h&m") || title.contains("barnes") || title.contains("target") || title.contains("starbucks") || title.contains("chipotle") || title.contains("chick-fil-a") || title.contains("panera") {
                txn.tags.append(tagSplurge)
            }
        }

        let sampleRules: [(String, RuleMatchType, String)] = [
            ("Whole Foods", .contains, "Groceries"),
            ("Trader Joe", .startsWith, "Groceries"),
            ("Kroger", .contains, "Groceries"),
            ("Chevron", .contains, "Gas & Fuel"),
            ("Shell", .exact, "Gas & Fuel"),
            ("Netflix", .contains, "Subscriptions"),
            ("Spotify", .contains, "Subscriptions"),
            ("Starbucks", .contains, "Food & Dining"),
            ("Chipotle", .contains, "Food & Dining"),
            ("DoorDash", .contains, "Food & Dining"),
            ("Uber", .startsWith, "Transportation"),
            ("Amazon", .contains, "Shopping"),
            ("Target", .contains, "Clothing"),
        ]
        for (i, (pattern, matchType, catName)) in sampleRules.enumerated() {
            let rule = CategoryRule(pattern: pattern, matchType: matchType, category: cat(catName), sortOrder: i)
            context.insert(rule)
        }

        let sampleAliases: [(String, String, RuleMatchType)] = [
            ("AMZN MKTP", "Amazon", .contains),
            ("WM SUPERCENTER", "Walmart", .contains),
            ("SQ *", "Square Payment", .startsWith),
            ("TST*", "Toast POS", .startsWith),
            ("PP*", "PayPal", .startsWith),
            ("PYMT VENMO", "Venmo", .contains),
        ]
        for (raw, clean, matchType) in sampleAliases {
            let alias = MerchantAlias(rawPattern: raw, cleanName: clean, matchType: matchType)
            context.insert(alias)
        }

        // Recalculate cached balances for all accounts
        for account in [checking, savings, creditCard, cash] {
            account.recalculateBalance()
        }
    }

    private static func fetchCategories(context: ModelContext) -> [Category] {
        let descriptor = FetchDescriptor<Category>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func randomDay(in monthDate: Date, calendar: Calendar) -> Date {
        let range = calendar.range(of: .day, in: .month, for: monthDate)!
        let day = Int.random(in: range)
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        components.hour = Int.random(in: 8...20)
        components.minute = Int.random(in: 0...59)
        return calendar.date(from: components) ?? monthDate
    }

    private static func firstWeekday(of monthDate: Date, weekday: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = 25
        return calendar.date(from: components) ?? monthDate
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
