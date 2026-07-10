import SwiftUI
import SwiftData

struct DataIntegrityView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var transactions: [Transaction]

    @State private var statusMessage: String?
    @State private var pendingRestore: URL?
    @State private var showingRestoreConfirm = false
    @State private var refreshToken = 0

    // MARK: - Checks

    /// Accounts whose cached balance has drifted from initialBalance + Σtransactions.
    private var balanceDriftAccounts: [(account: Account, expected: Decimal, drift: Decimal)] {
        accounts.compactMap { account in
            let expected = account.initialBalance + account.transactions.reduce(Decimal.zero) { $0 + $1.amount }
            let drift = account.currentBalance - expected
            return abs(drift) >= Decimal(0.01) ? (account, expected, drift) : nil
        }
    }

    /// Groups of transactions that look like duplicates (same account, day, amount, payee).
    private var duplicateGroups: [[Transaction]] {
        let calendar = Calendar.current
        var buckets: [String: [Transaction]] = [:]
        for txn in transactions {
            let day = calendar.startOfDay(for: txn.date).timeIntervalSince1970
            let key = "\(txn.account?.id.uuidString ?? "none")|\(day)|\(txn.amount)|\(txn.title.lowercased())"
            buckets[key, default: []].append(txn)
        }
        return buckets.values.filter { $0.count > 1 }
    }

    private var duplicateExtraCount: Int {
        duplicateGroups.reduce(0) { $0 + ($1.count - 1) }
    }

    /// Transactions with no account attached.
    private var orphanTransactions: [Transaction] {
        transactions.filter { $0.account == nil }
    }

    private var issueCount: Int {
        balanceDriftAccounts.count + (duplicateExtraCount > 0 ? 1 : 0) + (orphanTransactions.isEmpty ? 0 : 1)
    }

    var body: some View {
        Form {
            summarySection
            checksSection
            backupsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Data Health")
        .id(refreshToken)
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: issueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(issueCount == 0 ? AppTheme.income : AppTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(issueCount == 0 ? "Everything checks out" : "\(issueCount) issue\(issueCount == 1 ? "" : "s") found")
                        .font(.headline)
                    Text(issueCount == 0
                         ? "Balances reconcile and no duplicates or orphaned records were found."
                         : "Review the checks below — most can be fixed in one tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.income)
            }
        }
    }

    // MARK: - Checks

    private var checksSection: some View {
        Section("Checks") {
            // Balance drift
            if balanceDriftAccounts.isEmpty {
                checkRow(ok: true, title: "Account balances reconcile",
                         detail: "Every balance equals its opening balance plus all transactions.")
            } else {
                ForEach(balanceDriftAccounts, id: \.account.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        checkRow(ok: false, title: "\(item.account.name) balance is off",
                                 detail: "Shows \(CurrencyFormatter.shared.format(item.account.currentBalance, currency: item.account.currency)), should be \(CurrencyFormatter.shared.format(item.expected, currency: item.account.currency)) (off by \(CurrencyFormatter.shared.format(item.drift, currency: item.account.currency))).")
                        Button("Recalculate \(item.account.name)") {
                            item.account.recalculateBalance()
                            save("Recalculated \(item.account.name)")
                        }
                        .font(.caption.weight(.medium))
                    }
                }
                Button("Recalculate all balances") {
                    for account in accounts { account.recalculateBalance() }
                    save("All balances recalculated")
                }
                .foregroundStyle(AppTheme.accent(for: scheme))
            }

            // Duplicates
            if duplicateExtraCount == 0 {
                checkRow(ok: true, title: "No duplicate transactions",
                         detail: "No repeated transactions with the same date, amount and payee.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    checkRow(ok: false, title: "\(duplicateExtraCount) possible duplicate\(duplicateExtraCount == 1 ? "" : "s")",
                             detail: "Transactions sharing the same account, date, amount and payee. Keeping the first of each, the rest can be removed.")
                    Button("Remove \(duplicateExtraCount) duplicate\(duplicateExtraCount == 1 ? "" : "s")", role: .destructive) {
                        removeDuplicates()
                    }
                    .font(.caption.weight(.medium))
                }
            }

            // Orphans
            if orphanTransactions.isEmpty {
                checkRow(ok: true, title: "No orphaned transactions",
                         detail: "Every transaction belongs to an account.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    checkRow(ok: false, title: "\(orphanTransactions.count) transaction\(orphanTransactions.count == 1 ? "" : "s") with no account",
                             detail: "These aren't counted in any balance. You can delete them if they're leftovers.")
                    Button("Delete orphaned transactions", role: .destructive) {
                        for txn in orphanTransactions { context.delete(txn) }
                        save("Removed \(orphanTransactions.count) orphaned transactions")
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
    }

    private func checkRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? AppTheme.income : AppTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Backups

    private var backupsSection: some View {
        Section {
            if let last = BackupManager.lastAutomaticBackupDate {
                LabeledContent("Last automatic backup") {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No automatic backup yet — one is created on launch, once per day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let backups = BackupManager.listBackups()
            if backups.isEmpty {
                Text("No saved backups found.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(backups.prefix(8), id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backupDisplayName(url))
                                .font(.subheadline)
                            if let date = backupDate(url) {
                                Text(date, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Restore") {
                            pendingRestore = url
                            showingRestoreConfirm = true
                        }
                        .font(.caption.weight(.medium))
                    }
                }
            }
        } header: {
            Text("Automatic Backups")
        } footer: {
            Text("A full snapshot is saved automatically on first launch each day. The 10 most recent are kept. Restoring replaces all current data.")
        }
        .alert("Restore this backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { pendingRestore = nil }
            Button("Replace All Data", role: .destructive) { performRestore() }
        } message: {
            Text("This permanently replaces all current data with the contents of the selected backup. This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func save(_ message: String) {
        context.saveOrLog()
        statusMessage = message
        refreshToken += 1
    }

    private func removeDuplicates() {
        var removed = 0
        var affected = Set<PersistentIdentifier>()
        for group in duplicateGroups {
            // Keep the earliest-created (stable), delete the rest.
            let sorted = group.sorted { $0.date < $1.date }
            for txn in sorted.dropFirst() {
                if let acc = txn.account { affected.insert(acc.persistentModelID) }
                context.delete(txn)
                removed += 1
            }
        }
        context.saveOrLog()
        for account in accounts where affected.contains(account.persistentModelID) {
            account.recalculateBalance()
        }
        save("Removed \(removed) duplicate\(removed == 1 ? "" : "s")")
    }

    private func performRestore() {
        guard let url = pendingRestore else { return }
        do {
            let data = try Data(contentsOf: url)
            let summary = try BackupManager.restore(from: data, context: context)
            statusMessage = "Restored \(summary.accounts) accounts and \(summary.transactions) transactions."
            refreshToken += 1
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
        pendingRestore = nil
    }

    private func backupDisplayName(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("MintLeaf-AutoBackup-") { return "Automatic backup" }
        return name.replacingOccurrences(of: "MintLeaf-", with: "")
    }

    private func backupDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
