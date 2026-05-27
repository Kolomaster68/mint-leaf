import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExcelImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    let account: Account

    @State private var parsedSheets: [XLSXImporter.Sheet] = []
    @State private var selectedSheetID: Int?
    @State private var showingFilePicker = true
    @State private var errorMessage: String?
    @State private var normalizeNames = true
    @State private var detectDuplicates = true
    @State private var selectedRows: Set<Int> = []
    @State private var importResult: ImportResult?

    struct ImportResult {
        let imported: Int
        let duplicates: Int
        let skipped: Int
    }

    private var selectedSheet: XLSXImporter.Sheet? {
        parsedSheets.first(where: { $0.id == selectedSheetID })
    }

    struct ColumnMap {
        var date: Int?
        var title: Int?
        var amount: Int?
        var type: Int?
        var headerRowIndex: Int = 0
    }

    /// Find the real header row — it may not be the first row (e.g. a title row precedes it).
    private var columnMap: ColumnMap? {
        guard let sheet = selectedSheet else { return nil }
        // Scan the first few rows to find one that contains "date" and "description"/"amount"
        for (rowIndex, row) in sheet.rows.prefix(5).enumerated() {
            var map = ColumnMap()
            map.headerRowIndex = rowIndex
            for (i, header) in row.enumerated() {
                let lower = header.lowercased()
                if lower.contains("date") { map.date = i }
                else if lower.contains("description") || lower.contains("payee") || lower.contains("title") { map.title = i }
                else if lower.contains("amount") { map.amount = i }
                else if lower.contains("type") { map.type = i }
            }
            // A valid header must have at least date + one of title/amount
            if map.date != nil && (map.title != nil || map.amount != nil) {
                return map
            }
        }
        // Fallback: treat first row as header
        guard let headerRow = sheet.rows.first else { return nil }
        var map = ColumnMap()
        for (i, header) in headerRow.enumerated() {
            let lower = header.lowercased()
            if lower.contains("date") { map.date = i }
            else if lower.contains("description") || lower.contains("payee") || lower.contains("title") { map.title = i }
            else if lower.contains("amount") { map.amount = i }
            else if lower.contains("type") { map.type = i }
        }
        return map
    }

    /// Data rows (skip everything up to and including header row + skip TOTALS rows)
    private var dataRows: [[String]] {
        guard let sheet = selectedSheet, let map = columnMap else { return [] }
        return Array(sheet.rows.dropFirst(map.headerRowIndex + 1)).filter { row in
            // Skip totals/summary rows
            let first = row.first?.lowercased() ?? ""
            return !first.contains("total") && !first.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result = importResult {
                    resultView(result)
                } else if !parsedSheets.isEmpty {
                    importView
                } else {
                    ContentUnavailableView(
                        "Select an Excel File",
                        systemImage: "tablecells",
                        description: Text("Choose a .xlsx spreadsheet to import transactions from.")
                    )
                }
            }
            .navigationTitle("Import Spreadsheet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if importResult == nil && selectedSheet != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import Selected") { performImport() }
                            .disabled(selectedRows.isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [XLSXImporter.supportedType],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { loadExcel(url) }
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
        .macOSSheet(width: 720, height: 600)
    }

    private var importView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sheet selector
            if parsedSheets.count > 1 {
                HStack(spacing: 12) {
                    Text("Sheet:")
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $selectedSheetID) {
                        ForEach(parsedSheets) { sheet in
                            Text(sheet.name).tag(Optional(sheet.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSheetID) { _, _ in
                        // Auto-select all rows for new sheet
                        selectedRows = Set(0..<dataRows.count)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if let map = columnMap {
                // Column detection status
                HStack(spacing: 16) {
                    columnBadge("Date", detected: map.date != nil)
                    columnBadge("Description", detected: map.title != nil)
                    columnBadge("Amount", detected: map.amount != nil)
                    columnBadge("Type", detected: map.type != nil)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Transaction list
            List {
                Section("\(dataRows.count) transactions • \(selectedRows.count) selected") {
                    ForEach(Array(dataRows.enumerated()), id: \.offset) { index, row in
                        let parsed = parseRow(row)
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
                                Text(parsed.title)
                                    .font(.body)
                                    .lineLimit(1)
                                if let date = parsed.date {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(CurrencyFormatter.shared.format(parsed.amount))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(parsed.amount >= 0 ? .green : .primary)
                        }
                    }
                }
            }

            // Options & controls
            HStack {
                Button("Select All") {
                    selectedRows = Set(0..<dataRows.count)
                }
                Button("Deselect All") {
                    selectedRows.removeAll()
                }
                Spacer()
                Toggle("Detect duplicates", isOn: $detectDuplicates)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func columnBadge(_ label: String, detected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(detected ? .green : .orange)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultView(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent(for: scheme))
            Text("Import Complete")
                .font(.title2.bold())
            Text("\(result.imported) transactions imported")
            if result.duplicates > 0 {
                Text("\(result.duplicates) duplicates skipped")
                    .foregroundStyle(.orange)
            }
            if result.skipped > 0 {
                Text("\(result.skipped) rows skipped (missing data)")
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Data

    struct ParsedRow {
        let date: Date?
        let title: String
        let amount: Decimal
    }

    private func parseRow(_ row: [String]) -> ParsedRow {
        guard let map = columnMap else {
            return ParsedRow(date: nil, title: row.first ?? "", amount: 0)
        }

        let dateStr = map.date.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
        let title = map.title.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
        let amountStr = map.amount.flatMap { $0 < row.count ? row[$0] : nil } ?? "0"

        let date = XLSXImporter.parseDate(dateStr)

        let cleaned = amountStr
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        let amount = Decimal(string: cleaned) ?? 0

        return ParsedRow(date: date, title: title, amount: amount)
    }

    // MARK: - Actions

    private func loadExcel(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let result = try XLSXImporter.parse(url: url)
            parsedSheets = result.sheets
            if let first = parsedSheets.first {
                selectedSheetID = first.id
                // Use dataRows count (which now accounts for title rows)
                DispatchQueue.main.async {
                    selectedRows = Set(0..<dataRows.count)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        let rows = dataRows
        let existingTransactions = account.transactions
        var imported = 0
        var duplicates = 0
        var skipped = 0

        for index in selectedRows.sorted() {
            guard index < rows.count else { continue }
            let parsed = parseRow(rows[index])

            guard !parsed.title.isEmpty, parsed.date != nil else {
                skipped += 1
                continue
            }

            let title = normalizeNames ? MerchantNormalizer.normalize(parsed.title) : parsed.title
            let transaction = Transaction(
                amount: parsed.amount,
                title: title,
                date: parsed.date!,
                account: account
            )

            // Duplicate detection
            if detectDuplicates {
                let dupes = DuplicateDetector.findDuplicates(
                    incoming: [transaction],
                    existing: existingTransactions
                )
                if !dupes.isEmpty {
                    duplicates += 1
                    continue
                }
            }

            context.insert(transaction)
            imported += 1
        }

        // Apply categorization rules
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

        account.recalculateBalance()
        importResult = ImportResult(imported: imported, duplicates: duplicates, skipped: skipped)
    }
}
