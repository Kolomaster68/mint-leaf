import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BankFileImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]

    let account: Account

    @State private var showingPicker = false
    @State private var parsedTransactions: [ParsedBankTransaction] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var importResult: ImportResultInfo?
    @State private var error: String?
    @State private var fileName: String?
    @State private var fileInfo: String?

    struct ImportResultInfo {
        let imported: Int
        let duplicates: Int
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result = importResult {
                    resultView(result)
                } else if parsedTransactions.isEmpty {
                    pickFileView
                } else {
                    previewView
                }
            }
            .navigationTitle("Import Bank File")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importResult != nil ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 600, height: 500)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: bankFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
    }

    private var bankFileTypes: [UTType] {
        [
            UTType(filenameExtension: "ofx"),
            UTType(filenameExtension: "qfx"),
            UTType(filenameExtension: "qif"),
        ].compactMap { $0 }
    }

    // MARK: - Pick File

    private var pickFileView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent(for: scheme))

            Text("Import OFX, QFX, or QIF")
                .font(.title3.weight(.semibold))

            Text("These are the standard formats that most banks offer when you download or export your transactions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingPicker = true
            } label: {
                Label("Choose File", systemImage: "folder")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: scheme))

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = fileName {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                    }
                    if let info = fileInfo {
                        Text(info)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(selectedIDs.count) of \(parsedTransactions.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Select All") {
                    selectedIDs = Set(parsedTransactions.map(\.id))
                }
                .font(.caption)

                Button("Deselect All") {
                    selectedIDs = []
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Transaction list
            List {
                ForEach(parsedTransactions) { txn in
                    HStack(spacing: 12) {
                        Image(systemName: selectedIDs.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(txn.id) ? AppTheme.accent(for: scheme) : .secondary)
                            .onTapGesture {
                                if selectedIDs.contains(txn.id) {
                                    selectedIDs.remove(txn.id)
                                } else {
                                    selectedIDs.insert(txn.id)
                                }
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(txn.date, style: .date)
                                if !txn.memo.isEmpty {
                                    Text("· \(txn.memo)")
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(CurrencyFormatter.shared.format(txn.amount, currency: account.currency))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(txn.amount < 0 ? AppTheme.expense : AppTheme.income)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)

            Divider()

            // Import button
            HStack {
                Spacer()
                Button {
                    performImport()
                } label: {
                    Label("Import \(selectedIDs.count) Transactions", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent(for: scheme))
                .disabled(selectedIDs.isEmpty)
            }
            .padding(12)
        }
    }

    // MARK: - Result

    private func resultView(_ result: ImportResultInfo) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.income)

            Text("Import Complete")
                .font(.title3.weight(.semibold))

            VStack(spacing: 6) {
                Text("\(result.imported) transactions imported")
                    .font(.subheadline)
                if result.duplicates > 0 {
                    Text("\(result.duplicates) duplicates skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                error = "Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()

            do {
                let parsed: BankFileParseResult
                if ext == "qif" {
                    parsed = try QIFParser.parse(from: url)
                } else {
                    parsed = try OFXParser.parse(from: url)
                }

                parsedTransactions = parsed.transactions
                selectedIDs = Set(parsed.transactions.map(\.id))

                var infoParts: [String] = []
                if let currency = parsed.currency { infoParts.append(currency) }
                infoParts.append("\(parsed.transactions.count) transactions")
                if let first = parsed.transactions.first, let last = parsed.transactions.last {
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = .none
                    infoParts.append("\(df.string(from: first.date)) — \(df.string(from: last.date))")
                }
                fileInfo = infoParts.joined(separator: " · ")

                error = nil
            } catch {
                self.error = error.localizedDescription
            }

        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func performImport() {
        let selected = parsedTransactions.filter { selectedIDs.contains($0.id) }
        let existingTransactions = account.transactions
        var imported = 0
        var duplicates = 0

        for txn in selected {
            // Account is linked only after the duplicate check — relating an unmanaged
            // model to a persisted one gets it implicitly saved, so skipped duplicates
            // were quietly imported anyway.
            let transaction = Transaction(
                amount: txn.amount,
                title: txn.title,
                date: txn.date,
                notes: txn.memo
            )

            // Check for duplicates
            let isDupe = DuplicateDetector.findDuplicates(incoming: [transaction], existing: existingTransactions)
            if !isDupe.isEmpty {
                duplicates += 1
                continue
            }

            transaction.account = account
            context.insert(transaction)

            // Auto-categorise using rules
            RulesEngine.applyRules(to: transaction, rules: rules, aliases: aliases)
            imported += 1
        }

        account.recalculateBalance()
        context.saveOrLog()

        importResult = ImportResultInfo(imported: imported, duplicates: duplicates)
    }
}
