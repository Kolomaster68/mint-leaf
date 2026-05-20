import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    let account: Account

    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var columns: [CSVColumn] = []
    @State private var importResult: CSVImportResult?
    @State private var showingFilePicker = true
    @State private var errorMessage: String?
    @State private var normalizeNames = true
    @State private var detectDuplicates = true

    var body: some View {
        NavigationStack {
            Group {
                if columns.isEmpty {
                    ContentUnavailableView(
                        "Select a CSV File",
                        systemImage: "doc.text",
                        description: Text("Choose a CSV, OFX, or QIF file to import.")
                    )
                } else if let result = importResult {
                    resultView(result)
                } else {
                    mappingView
                }
            }
            .navigationTitle("Import Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !columns.isEmpty && importResult == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { performImport() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadFile(url)
                    }
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
        .macOSSheet(width: 620, height: 520)
    }

    private var mappingView: some View {
        Form {
            Section("Preview (\(rows.count) rows)") {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading) {
                        HStack {
                            ForEach(headers, id: \.self) { header in
                                Text(header)
                                    .font(.caption.bold())
                                    .frame(width: 120)
                            }
                        }
                        Divider()
                        ForEach(rows.prefix(3), id: \.self) { row in
                            HStack {
                                ForEach(row.indices, id: \.self) { i in
                                    Text(row[i])
                                        .font(.caption)
                                        .frame(width: 120, alignment: .leading)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }

            Section("Column Mapping") {
                ForEach($columns) { $column in
                    HStack {
                        Text(column.header)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $column.mapping) {
                            ForEach(CSVFieldMapping.allCases) { mapping in
                                Text(mapping.rawValue).tag(mapping)
                            }
                        }
                    }
                }
            }

            Section("Smart Import") {
                Toggle("Normalize merchant names", isOn: $normalizeNames)
                Toggle("Detect duplicates", isOn: $detectDuplicates)
            }
        }
    }

    private func resultView(_ result: CSVImportResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.accent(for: scheme))
            Text("Import Complete")
                .font(.title2.bold())
            Text("\(result.imported) transactions imported")
            if result.duplicatesDetected > 0 {
                Text("\(result.duplicatesDetected) potential duplicates skipped")
                    .foregroundStyle(.orange)
            }
            if result.skipped > 0 {
                Text("\(result.skipped) rows skipped")
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func loadFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let (h, r) = try CSVImporter.parseCSV(from: url)
            headers = h
            rows = r
            columns = h.enumerated().map { index, header in
                var col = CSVColumn(index: index, header: header)
                let lower = header.lowercased()
                if lower.contains("date") { col.mapping = .date }
                else if lower.contains("amount") { col.mapping = .amount }
                else if lower.contains("debit") { col.mapping = .debit }
                else if lower.contains("credit") { col.mapping = .credit }
                else if lower.contains("payee") || lower.contains("description") || lower.contains("name") { col.mapping = .title }
                else if lower.contains("memo") || lower.contains("note") { col.mapping = .notes }
                else if lower.contains("category") { col.mapping = .category }
                return col
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performImport() {
        let result = CSVImporter.importTransactions(
            rows: rows,
            columns: columns,
            account: account,
            context: context
        )

        if normalizeNames {
            for txn in account.transactions {
                txn.title = MerchantNormalizer.normalize(txn.title)
            }
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

        importResult = result
    }
}
