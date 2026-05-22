import SwiftUI
import SwiftData

struct PDFImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    let account: Account

    @State private var parsedStatement: ParsedStatement?
    @State private var selectedRows: Set<Int> = []
    @State private var showingFilePicker = true
    @State private var errorMessage: String?
    @State private var importCount = 0
    @State private var duplicatesSkipped = 0
    @State private var didImport = false
    @State private var detectDuplicates = true
    @State private var setOpeningBalance = false
    @State private var detectedOpeningBalance: Decimal?

    var body: some View {
        NavigationStack {
            Group {
                if didImport {
                    resultView
                } else if let statement = parsedStatement {
                    if statement.transactions.isEmpty {
                        debugView(statement)
                    } else {
                        parsedView(statement)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a PDF Statement",
                        systemImage: "doc.richtext",
                        description: Text("Choose a bank statement PDF to parse.")
                    )
                }
            }
            .navigationTitle("Import PDF Statement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if parsedStatement != nil && !didImport {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import Selected") { performImport() }
                            .disabled(selectedRows.isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { loadPDF(url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .macOSSheet(width: 700, height: 580)
    }

    private func parsedView(_ statement: ParsedStatement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bank = statement.bankName {
                Text("Detected: \(bank)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Opening/closing balance detection
            if statement.openingBalance != nil || statement.closingBalance != nil {
                HStack(spacing: 16) {
                    if let opening = statement.openingBalance {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Opening Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(opening))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if let closing = statement.closingBalance {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Closing Balance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(closing))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer()
                    if let opening = statement.openingBalance, account.transactions.isEmpty {
                        Toggle("Set as account opening balance", isOn: $setOpeningBalance)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .onAppear { detectedOpeningBalance = opening; setOpeningBalance = true }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            List {
                Section("\(statement.transactions.count) transactions found") {
                    ForEach(Array(statement.transactions.enumerated()), id: \.offset) { index, txn in
                        HStack {
                            Button {
                                if selectedRows.contains(index) {
                                    selectedRows.remove(index)
                                } else {
                                    selectedRows.insert(index)
                                }
                            } label: {
                                Image(systemName: selectedRows.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedRows.contains(index) ? AppTheme.accent(for: scheme) : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading) {
                                Text(txn.title)
                                    .font(.body)
                                    .lineLimit(1)
                                if let date = txn.date {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if let amount = txn.amount {
                                Text(CurrencyFormatter.shared.format(amount))
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Select All") {
                    selectedRows = Set(0..<(parsedStatement?.transactions.count ?? 0))
                }
                Button("Deselect All") {
                    selectedRows.removeAll()
                }
                Spacer()
                Toggle("Detect duplicates", isOn: $detectDuplicates)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal)
        }
    }

    private func debugView(_ statement: ParsedStatement) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("No transactions detected")
                .font(.title2.bold())
            Text("The parser couldn't find transaction rows in this PDF (\(statement.pageCount) pages). The raw text extracted is shown below — this helps debug the format.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let bank = statement.bankName {
                Text("Detected bank: \(bank)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(String(statement.rawText.prefix(3000)))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Button("Try Again") {
                parsedStatement = nil
                showingFilePicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var resultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent(for: scheme))
            Text("Import Complete")
                .font(.title2.bold())
            Text("\(importCount) transactions imported from PDF")
            if duplicatesSkipped > 0 {
                Text("\(duplicatesSkipped) duplicates skipped")
                    .foregroundStyle(.orange)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func loadPDF(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            parsedStatement = try PDFStatementParser.parse(url: url)
            if let count = parsedStatement?.transactions.count {
                selectedRows = Set(0..<count)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        guard let statement = parsedStatement else { return }
        var count = 0
        var dupes = 0
        let existingTransactions = account.transactions

        for index in selectedRows.sorted() {
            let parsed = statement.transactions[index]
            let amount = parsed.amount ?? 0
            let title = MerchantNormalizer.normalize(parsed.title)
            let transaction = Transaction(
                amount: amount,
                title: title,
                date: parsed.date ?? Date(),
                account: account
            )

            if detectDuplicates {
                let matches = DuplicateDetector.findDuplicates(
                    incoming: [transaction],
                    existing: existingTransactions
                )
                if !matches.isEmpty {
                    dupes += 1
                    continue
                }
            }

            context.insert(transaction)
            count += 1
        }

        RulesEngine.applyAll(
            transactions: account.transactions.filter { $0.category == nil },
            rules: rules,
            aliases: aliases
        )

        let _ = AutoCategorizer.categorizeAll(
            transactions: account.transactions.filter { $0.category == nil },
            categories: categories,
            rules: rules
        )

        // Set opening balance if detected and toggled on
        if setOpeningBalance, let opening = detectedOpeningBalance {
            account.initialBalance = opening
        }

        importCount = count
        duplicatesSkipped = dupes
        didImport = true
    }
}
