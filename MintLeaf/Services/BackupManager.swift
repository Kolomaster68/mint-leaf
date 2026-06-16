import Foundation
import SwiftData

// MARK: - Backup File Format
//
// A single self-contained snapshot of every model in the app. Relationships are
// captured by UUID so they can be re-wired on restore. The whole thing is a flat
// set of arrays — decode, recreate every object, then connect them in a second pass.

struct MintLeafBackup: Codable {
    var formatVersion: Int = 1
    var appVersion: String
    var createdAt: Date

    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var transactions: [TransactionDTO]
    var budgets: [BudgetDTO]
    var budgetItems: [BudgetItemDTO]
    var scheduled: [ScheduledDTO]
    var rules: [RuleDTO]
    var aliases: [AliasDTO]
    var goals: [GoalDTO]
    var tags: [TagDTO]

    struct AccountDTO: Codable {
        var id: UUID
        var name: String
        var type: String
        var currency: String
        var initialBalance: Decimal
        var icon: String
        var colorHex: String
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var cachedBalance: Decimal
        var statementDay: Int?
        var paymentDueOffsetDays: Int?
        var paymentDueDay: Int?
        var paymentSourceAccountID: UUID?
        var overdraftLimit: Decimal?
        var overdraftEAR: Decimal?
        var unarrangedOverdraftFee: Decimal?
        var purchaseAPR: Decimal?
    }

    struct CategoryDTO: Codable {
        var id: UUID
        var name: String
        var icon: String
        var colorHex: String
        var isIncome: Bool
        var sortOrder: Int
        var parentCategoryID: UUID?
    }

    struct TransactionDTO: Codable {
        var id: UUID
        var amount: Decimal
        var title: String
        var notes: String
        var date: Date
        var isReconciled: Bool
        var checkNumber: String?
        var location: String?
        var transferPairID: UUID?
        var accountID: UUID?
        var categoryID: UUID?
        var transferDestinationID: UUID?
        var scheduledSourceID: UUID?
        var tagIDs: [UUID]
    }

    struct BudgetDTO: Codable {
        var id: UUID
        var name: String
        var period: String
        var startDate: Date
        var createdAt: Date
    }

    struct BudgetItemDTO: Codable {
        var id: UUID
        var amount: Decimal
        var categoryID: UUID?
        var budgetID: UUID?
    }

    struct ScheduledDTO: Codable {
        var id: UUID
        var amount: Decimal
        var title: String
        var notes: String
        var frequency: String
        var nextDate: Date
        var endDate: Date?
        var isActive: Bool
        var isSubscription: Bool
        var currency: String
        var accountID: UUID?
        var categoryID: UUID?
    }

    struct RuleDTO: Codable {
        var id: UUID
        var pattern: String
        var matchType: String
        var sortOrder: Int
        var isEnabled: Bool
        var createdAt: Date
        var categoryID: UUID?
    }

    struct AliasDTO: Codable {
        var id: UUID
        var rawPattern: String
        var cleanName: String
        var matchType: String
        var isEnabled: Bool
    }

    struct GoalDTO: Codable {
        var id: UUID
        var name: String
        var icon: String
        var colorHex: String
        var targetAmount: Decimal
        var savedAmount: Decimal
        var targetDate: Date?
        var notes: String
        var isWishlistItem: Bool
        var linkURL: String?
        var imageURL: String?
        var isPurchased: Bool
        var createdDate: Date
        var sortOrder: Int
        var accountID: UUID?
    }

    struct TagDTO: Codable {
        var id: UUID
        var name: String
        var colorHex: String
        var sortOrder: Int
    }
}

// MARK: - Backup Manager

enum BackupManager {

    struct Summary {
        var accounts = 0
        var transactions = 0
        var budgets = 0
        var scheduled = 0
        var rules = 0
        var aliases = 0
        var goals = 0
        var tags = 0
        var categories = 0
    }

    // MARK: Export

    @MainActor
    static func export(context: ModelContext) throws -> Data {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let accounts = fetch(Account.self)
        let categories = fetch(Category.self)
        let transactions = fetch(Transaction.self)
        let budgets = fetch(Budget.self)
        let budgetItems = fetch(BudgetItem.self)
        let scheduled = fetch(ScheduledTransaction.self)
        let rules = fetch(CategoryRule.self)
        let aliases = fetch(MerchantAlias.self)
        let goals = fetch(Goal.self)
        let tags = fetch(Tag.self)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let backup = MintLeafBackup(
            appVersion: appVersion,
            createdAt: Date(),
            accounts: accounts.map { a in
                .init(id: a.id, name: a.name, type: a.type.rawValue, currency: a.currency,
                      initialBalance: a.initialBalance, icon: a.icon, colorHex: a.colorHex,
                      sortOrder: a.sortOrder, isArchived: a.isArchived, createdAt: a.createdAt,
                      cachedBalance: a.cachedBalance, statementDay: a.statementDay,
                      paymentDueOffsetDays: a.paymentDueOffsetDays, paymentDueDay: a.paymentDueDay,
                      paymentSourceAccountID: a.paymentSourceAccountID, overdraftLimit: a.overdraftLimit,
                      overdraftEAR: a.overdraftEAR, unarrangedOverdraftFee: a.unarrangedOverdraftFee,
                      purchaseAPR: a.purchaseAPR)
            },
            categories: categories.map { c in
                .init(id: c.id, name: c.name, icon: c.icon, colorHex: c.colorHex,
                      isIncome: c.isIncome, sortOrder: c.sortOrder, parentCategoryID: c.parentCategory?.id)
            },
            transactions: transactions.map { t in
                .init(id: t.id, amount: t.amount, title: t.title, notes: t.notes, date: t.date,
                      isReconciled: t.isReconciled, checkNumber: t.checkNumber, location: t.location,
                      transferPairID: t.transferPairID,
                      accountID: t.account?.id, categoryID: t.category?.id,
                      transferDestinationID: t.transferDestination?.id,
                      scheduledSourceID: t.scheduledSource?.id, tagIDs: t.tags.map(\.id))
            },
            budgets: budgets.map { b in
                .init(id: b.id, name: b.name, period: b.period.rawValue, startDate: b.startDate, createdAt: b.createdAt)
            },
            budgetItems: budgetItems.map { i in
                .init(id: i.id, amount: i.amount, categoryID: i.category?.id, budgetID: i.budget?.id)
            },
            scheduled: scheduled.map { s in
                .init(id: s.id, amount: s.amount, title: s.title, notes: s.notes,
                      frequency: s.frequency.rawValue, nextDate: s.nextDate, endDate: s.endDate,
                      isActive: s.isActive, isSubscription: s.isSubscription, currency: s.currency,
                      accountID: s.account?.id, categoryID: s.category?.id)
            },
            rules: rules.map { r in
                .init(id: r.id, pattern: r.pattern, matchType: r.matchType.rawValue,
                      sortOrder: r.sortOrder, isEnabled: r.isEnabled, createdAt: r.createdAt,
                      categoryID: r.category?.id)
            },
            aliases: aliases.map { m in
                .init(id: m.id, rawPattern: m.rawPattern, cleanName: m.cleanName,
                      matchType: m.matchType.rawValue, isEnabled: m.isEnabled)
            },
            goals: goals.map { g in
                .init(id: g.id, name: g.name, icon: g.icon, colorHex: g.colorHex,
                      targetAmount: g.targetAmount, savedAmount: g.savedAmount, targetDate: g.targetDate,
                      notes: g.notes, isWishlistItem: g.isWishlistItem, linkURL: g.linkURL,
                      imageURL: g.imageURL, isPurchased: g.isPurchased, createdDate: g.createdDate,
                      sortOrder: g.sortOrder, accountID: g.account?.id)
            },
            tags: tags.map { t in
                .init(id: t.id, name: t.name, colorHex: t.colorHex, sortOrder: t.sortOrder)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: Restore

    /// Replaces ALL existing data with the contents of the backup.
    @MainActor
    @discardableResult
    static func restore(from data: Data, context: ModelContext) throws -> Summary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(MintLeafBackup.self, from: data)

        // 1. Wipe everything currently in the store.
        try wipeAll(context: context)

        // 2. Create all objects without relationships, keyed by UUID.
        var accountsByID: [UUID: Account] = [:]
        var categoriesByID: [UUID: Category] = [:]
        var transactionsByID: [UUID: Transaction] = [:]
        var budgetsByID: [UUID: Budget] = [:]
        var scheduledByID: [UUID: ScheduledTransaction] = [:]
        var tagsByID: [UUID: Tag] = [:]

        for dto in backup.accounts {
            let a = Account(name: dto.name,
                            type: AccountType(rawValue: dto.type) ?? .other,
                            currency: dto.currency,
                            initialBalance: dto.initialBalance,
                            icon: dto.icon,
                            colorHex: dto.colorHex,
                            sortOrder: dto.sortOrder)
            a.id = dto.id
            a.isArchived = dto.isArchived
            a.createdAt = dto.createdAt
            a.cachedBalance = dto.cachedBalance
            a.statementDay = dto.statementDay
            a.paymentDueOffsetDays = dto.paymentDueOffsetDays
            a.paymentDueDay = dto.paymentDueDay
            a.paymentSourceAccountID = dto.paymentSourceAccountID
            a.overdraftLimit = dto.overdraftLimit
            a.overdraftEAR = dto.overdraftEAR
            a.unarrangedOverdraftFee = dto.unarrangedOverdraftFee
            a.purchaseAPR = dto.purchaseAPR
            context.insert(a)
            accountsByID[dto.id] = a
        }

        for dto in backup.categories {
            let c = Category(name: dto.name, icon: dto.icon, colorHex: dto.colorHex,
                             isIncome: dto.isIncome, sortOrder: dto.sortOrder)
            c.id = dto.id
            context.insert(c)
            categoriesByID[dto.id] = c
        }

        for dto in backup.tags {
            let t = Tag(name: dto.name, colorHex: dto.colorHex, sortOrder: dto.sortOrder)
            t.id = dto.id
            context.insert(t)
            tagsByID[dto.id] = t
        }

        for dto in backup.budgets {
            let b = Budget(name: dto.name,
                           period: BudgetPeriod(rawValue: dto.period) ?? .monthly,
                           startDate: dto.startDate)
            b.id = dto.id
            b.createdAt = dto.createdAt
            context.insert(b)
            budgetsByID[dto.id] = b
        }

        for dto in backup.scheduled {
            let s = ScheduledTransaction(amount: dto.amount, title: dto.title,
                                         frequency: RecurrenceFrequency(rawValue: dto.frequency) ?? .monthly,
                                         nextDate: dto.nextDate,
                                         isSubscription: dto.isSubscription,
                                         currency: dto.currency)
            s.id = dto.id
            s.notes = dto.notes
            s.endDate = dto.endDate
            s.isActive = dto.isActive
            context.insert(s)
            scheduledByID[dto.id] = s
        }

        for dto in backup.transactions {
            let t = Transaction(amount: dto.amount, title: dto.title, date: dto.date, notes: dto.notes)
            t.id = dto.id
            t.isReconciled = dto.isReconciled
            t.checkNumber = dto.checkNumber
            t.location = dto.location
            t.transferPairID = dto.transferPairID
            context.insert(t)
            transactionsByID[dto.id] = t
        }

        // 3. Wire relationships.
        for dto in backup.categories {
            if let pid = dto.parentCategoryID {
                categoriesByID[dto.id]?.parentCategory = categoriesByID[pid]
            }
        }

        for dto in backup.transactions {
            guard let t = transactionsByID[dto.id] else { continue }
            if let aid = dto.accountID { t.account = accountsByID[aid] }
            if let cid = dto.categoryID { t.category = categoriesByID[cid] }
            if let did = dto.transferDestinationID { t.transferDestination = accountsByID[did] }
            if let sid = dto.scheduledSourceID { t.scheduledSource = scheduledByID[sid] }
            t.tags = dto.tagIDs.compactMap { tagsByID[$0] }
        }

        for dto in backup.budgetItems {
            let item = BudgetItem(amount: dto.amount)
            item.id = dto.id
            if let cid = dto.categoryID { item.category = categoriesByID[cid] }
            if let bid = dto.budgetID { item.budget = budgetsByID[bid] }
            context.insert(item)
        }

        for dto in backup.scheduled {
            guard let s = scheduledByID[dto.id] else { continue }
            if let aid = dto.accountID { s.account = accountsByID[aid] }
            if let cid = dto.categoryID { s.category = categoriesByID[cid] }
        }

        for dto in backup.rules {
            let r = CategoryRule(pattern: dto.pattern,
                                 matchType: RuleMatchType(rawValue: dto.matchType) ?? .contains,
                                 sortOrder: dto.sortOrder)
            r.id = dto.id
            r.isEnabled = dto.isEnabled
            r.createdAt = dto.createdAt
            if let cid = dto.categoryID { r.category = categoriesByID[cid] }
            context.insert(r)
        }

        for dto in backup.aliases {
            let m = MerchantAlias(rawPattern: dto.rawPattern, cleanName: dto.cleanName,
                                  matchType: RuleMatchType(rawValue: dto.matchType) ?? .contains)
            m.id = dto.id
            m.isEnabled = dto.isEnabled
            context.insert(m)
        }

        for dto in backup.goals {
            let g = Goal(name: dto.name, icon: dto.icon, colorHex: dto.colorHex,
                         targetAmount: dto.targetAmount, savedAmount: dto.savedAmount,
                         targetDate: dto.targetDate, notes: dto.notes,
                         isWishlistItem: dto.isWishlistItem, linkURL: dto.linkURL,
                         imageURL: dto.imageURL, sortOrder: dto.sortOrder)
            g.id = dto.id
            g.isPurchased = dto.isPurchased
            g.createdDate = dto.createdDate
            if let aid = dto.accountID { g.account = accountsByID[aid] }
            context.insert(g)
        }

        try context.save()

        // Recalculate cached balances from restored transactions to be safe.
        for account in accountsByID.values {
            account.recalculateBalance()
        }
        try context.save()

        var summary = Summary()
        summary.accounts = backup.accounts.count
        summary.transactions = backup.transactions.count
        summary.budgets = backup.budgets.count
        summary.scheduled = backup.scheduled.count
        summary.rules = backup.rules.count
        summary.aliases = backup.aliases.count
        summary.goals = backup.goals.count
        summary.tags = backup.tags.count
        summary.categories = backup.categories.count
        return summary
    }

    // MARK: - Automatic Backups

    /// Folder where automatic backups are stored.
    static func backupsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("MintLeaf-Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Date of the most recent automatic backup, if any.
    static var lastAutomaticBackupDate: Date? {
        UserDefaults.standard.object(forKey: "lastAutoBackupDate") as? Date
    }

    /// Writes a timestamped backup at most once per day, then prunes to the newest `keepLast`.
    /// Safe to call on every launch — it throttles and silently no-ops on failure.
    @MainActor
    static func performAutomaticBackup(context: ModelContext, keepLast: Int = 10) {
        // Throttle to once per calendar day.
        if let last = lastAutomaticBackupDate, Calendar.current.isDateInToday(last) { return }

        // Don't back up an empty store (e.g. fresh install before seeding).
        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        let txnCount = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        guard accountCount > 0 || txnCount > 0 else { return }

        guard let dir = backupsDirectory() else { return }
        do {
            let data = try export(context: context)
            let stamp = Self.fileTimestamp()
            let url = dir.appendingPathComponent("MintLeaf-AutoBackup-\(stamp).json")
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: "lastAutoBackupDate")
            pruneBackups(in: dir, keepLast: keepLast)
        } catch {
            // Backups are best-effort — never disrupt launch.
        }
    }

    /// All backup files (auto + manual saved here), newest first.
    static func listBackups() -> [URL] {
        guard let dir = backupsDirectory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    private static func pruneBackups(in dir: URL, keepLast: Int) {
        let all = listBackups().filter { $0.lastPathComponent.hasPrefix("MintLeaf-AutoBackup-") }
        guard all.count > keepLast else { return }
        for url in all.dropFirst(keepLast) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    @MainActor
    private static func wipeAll(context: ModelContext) throws {
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for item in items { context.delete(item) }
        }
        // Order: dependents first to keep things tidy.
        deleteAll(Transaction.self)
        deleteAll(BudgetItem.self)
        deleteAll(Budget.self)
        deleteAll(ScheduledTransaction.self)
        deleteAll(CategoryRule.self)
        deleteAll(MerchantAlias.self)
        deleteAll(Goal.self)
        deleteAll(Tag.self)
        deleteAll(Category.self)
        deleteAll(Account.self)
        try context.save()
    }
}
