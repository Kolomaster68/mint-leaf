import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingCSVImport = false
    @State private var showingPDFImport = false
    @State private var showingExcelImport = false
    @State private var showingExporter = false
    @State private var selectedAccountForImport: Account?
    @State private var importType: ImportType?
    @State private var csvContent = ""
    @State private var exportScope: ExportScope = .all
    @State private var exportAccountID: PersistentIdentifier?

    // Backup & restore
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var backupData = Data()
    @State private var showingRestoreConfirm = false
    @State private var pendingRestoreData: Data?
    @State private var backupStatus: String?
    @State private var backupError: String?

    enum ImportType: Identifiable {
        case csv, pdf, excel, bankFile
        var id: String {
            switch self {
            case .csv: return "csv"
            case .pdf: return "pdf"
            case .excel: return "excel"
            case .bankFile: return "bankFile"
            }
        }
    }

    enum ExportScope {
        case all
        case account
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                importSection
                Divider()
                    .padding(.horizontal)
                exportSection
                Divider()
                    .padding(.horizontal)
                backupSection
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Import / Export")
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: BackupDocument(data: backupData),
            contentType: .json,
            defaultFilename: "MintLeaf-Backup-\(exportDateString)"
        ) { _ in }
        .fileImporter(
            isPresented: $showingBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleBackupFile(result)
        }
        .alert("Restore from backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { pendingRestoreData = nil }
            Button("Replace All Data", role: .destructive) { performRestore() }
        } message: {
            Text("This will permanently replace ALL current data — accounts, transactions, budgets, goals, rules and tags — with the contents of the backup file. This cannot be undone.")
        }
        .sheet(item: $importType) { type in
            if let account = selectedAccountForImport {
                switch type {
                case .csv:
                    CSVImportView(account: account)
                case .pdf:
                    PDFImportView(account: account)
                case .excel:
                    ExcelImportView(account: account)
                case .bankFile:
                    BankFileImportView(account: account)
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvContent),
            contentType: .commaSeparatedText,
            defaultFilename: "MintLeaf-Export-\(exportDateString).csv"
        ) { _ in }
        .onAppear {
            if selectedAccountForImport == nil, let first = accounts.first {
                selectedAccountForImport = first
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import Transactions", systemImage: "square.and.arrow.down")
                .font(.title3.bold())
                .padding(.horizontal)

            if accounts.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Create an account first before importing transactions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            } else {
                // Account picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import into account:")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(accounts) { account in
                            accountChip(account)
                        }
                    }
                }
                .padding(.horizontal)

                // Format cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    importCard(
                        title: "CSV",
                        icon: "tablecells",
                        description: "Comma-separated values",
                        color: .blue,
                        type: .csv
                    )
                    importCard(
                        title: "Bank File",
                        icon: "building.columns",
                        description: "OFX, QFX, or QIF bank exports",
                        color: .teal,
                        type: .bankFile
                    )
                    importCard(
                        title: "PDF Statement",
                        icon: "doc.richtext",
                        description: "Bank or credit card PDFs",
                        color: .red,
                        type: .pdf
                    )
                    importCard(
                        title: "Spreadsheet",
                        icon: "tablecells.badge.ellipsis",
                        description: "Excel .xlsx workbooks",
                        color: .green,
                        type: .excel
                    )
                }
                .padding(.horizontal)

                // Info text
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Duplicate transactions are automatically detected and skipped during import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }

    private func accountChip(_ account: Account) -> some View {
        Button {
            selectedAccountForImport = account
        } label: {
            HStack(spacing: 6) {
                Image(systemName: account.icon)
                    .font(.caption)
                Text(account.name)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedAccountForImport?.id == account.id
                    ? AppTheme.accent(for: scheme).opacity(0.15)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selectedAccountForImport?.id == account.id
                            ? AppTheme.accent(for: scheme)
                            : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func importCard(title: String, icon: String, description: String, color: Color, type: ImportType) -> some View {
        Button {
            guard selectedAccountForImport != nil else { return }
            importType = type
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(height: 30)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(selectedAccountForImport == nil ? 0.5 : 1.0)
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export Data", systemImage: "square.and.arrow.up")
                .font(.title3.bold())
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                // Scope picker
                Text("Export scope:")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Scope", selection: $exportScope) {
                    Text("All Accounts").tag(ExportScope.all)
                    Text("Single Account").tag(ExportScope.account)
                }
                .pickerStyle(.segmented)

                if exportScope == .account {
                    Picker("Account", selection: $exportAccountID) {
                        Text("Select account...").tag(nil as PersistentIdentifier?)
                        ForEach(accounts) { account in
                            HStack {
                                Image(systemName: account.icon)
                                Text(account.name)
                            }
                            .tag(Optional(account.persistentModelID))
                        }
                    }
                }

                // Export info
                let count = transactionCount
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(AppTheme.accent(for: scheme))
                    VStack(alignment: .leading) {
                        Text("\(count) transactions")
                            .font(.subheadline.weight(.medium))
                        Text("CSV format with date, account, payee, amount, category, notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    csvContent = buildExport()
                    showingExporter = true
                } label: {
                    Label("Export as CSV", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: scheme))
                .disabled(count == 0)
            }
            .padding()
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Backup & Restore Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Backup & Restore", systemImage: "externaldrive.badge.timemachine")
                .font(.title3.bold())
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppTheme.accent(for: scheme))
                    Text("A full snapshot of everything — accounts, transactions, subscriptions, bills, goals, budgets, rules and tags — in a single file. Save one before updating the app, then restore it in one tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        createBackup()
                    } label: {
                        Label("Create Backup", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent(for: scheme))

                    Button {
                        showingBackupImporter = true
                    } label: {
                        Label("Restore Backup", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let backupStatus {
                    Label(backupStatus, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.income)
                }
                if let backupError {
                    Label(backupError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    private func createBackup() {
        backupError = nil
        backupStatus = nil
        do {
            backupData = try BackupManager.export(context: context)
            showingBackupExporter = true
        } catch {
            backupError = "Couldn't create backup: \(error.localizedDescription)"
        }
    }

    private func handleBackupFile(_ result: Result<[URL], Error>) {
        backupError = nil
        backupStatus = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                backupError = "Cannot access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                pendingRestoreData = try Data(contentsOf: url)
                showingRestoreConfirm = true
            } catch {
                backupError = "Couldn't read file: \(error.localizedDescription)"
            }
        case .failure(let err):
            backupError = err.localizedDescription
        }
    }

    private func performRestore() {
        guard let data = pendingRestoreData else { return }
        do {
            let summary = try BackupManager.restore(from: data, context: context)
            backupStatus = "Restored \(summary.accounts) accounts, \(summary.transactions) transactions, \(summary.scheduled) scheduled, \(summary.goals) goals, \(summary.tags) tags."
        } catch {
            backupError = "Restore failed: \(error.localizedDescription)"
        }
        pendingRestoreData = nil
    }

    // MARK: - Helpers

    private var transactionCount: Int {
        switch exportScope {
        case .all:
            return accounts.reduce(0) { $0 + $1.transactions.count }
        case .account:
            guard let id = exportAccountID,
                  let account = accounts.first(where: { $0.persistentModelID == id }) else { return 0 }
            return account.transactions.count
        }
    }

    private var exportDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func buildExport() -> String {
        var lines = ["Date,Account,Payee,Amount,Category,Notes,Reconciled"]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let accountsToExport: [Account]
        switch exportScope {
        case .all:
            accountsToExport = accounts
        case .account:
            if let id = exportAccountID,
               let account = accounts.first(where: { $0.persistentModelID == id }) {
                accountsToExport = [account]
            } else {
                accountsToExport = []
            }
        }

        for account in accountsToExport {
            for txn in account.transactions.sorted(by: { $0.date < $1.date }) {
                let date = dateFormatter.string(from: txn.date)
                let acct = csvEscape(account.name)
                let payee = csvEscape(txn.title)
                let amount = "\(txn.amount)"
                let category = csvEscape(txn.category?.name ?? "")
                let notes = csvEscape(txn.notes)
                let reconciled = txn.isReconciled ? "Yes" : "No"
                lines.append("\(date),\(acct),\(payee),\(amount),\(category),\(notes),\(reconciled)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
