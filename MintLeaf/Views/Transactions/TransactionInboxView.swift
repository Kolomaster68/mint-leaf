import SwiftUI
import SwiftData

struct TransactionInboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appReduceMotion) private var reduceMotion
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \CategoryRule.sortOrder) private var rules: [CategoryRule]
    @Query private var aliases: [MerchantAlias]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var lastAutoResult: (categorized: Int, needsReview: Int)?
    @State private var selectedIDs: Set<UUID> = []
    @State private var bulkCategory: Category?
    @State private var showingBulkPicker = false

    private var uncategorized: [Transaction] {
        allTransactions.filter { $0.category == nil }
    }

    private var isSelecting: Bool { !selectedIDs.isEmpty }

    var body: some View {
        List(selection: $selectedIDs) {
            if let result = lastAutoResult, result.categorized > 0 {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(result.categorized) auto-categorized")
                            .font(.subheadline)
                        if result.needsReview > 0 {
                            Text("· \(result.needsReview) need review")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !uncategorized.isEmpty {
                Section("Uncategorized (\(uncategorized.count))") {
                    ForEach(uncategorized) { transaction in
                        InboxTransactionRow(
                            transaction: transaction,
                            categories: categories,
                            rules: rules,
                            context: context
                        )
                        .tag(transaction.id)
                        .swipeActions(edge: .leading) {
                            if let suggestion = AutoCategorizer.categorize(transaction: transaction, categories: categories, rules: rules) {
                                Button {
                                    withAnimation(reduceMotion ? .none : .default) {
                                        transaction.category = suggestion.category
                                        RulesEngine.learnRule(from: transaction, context: context)
                                    }
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                // Skip just dismisses the swipe
                            } label: {
                                Label("Skip", systemImage: "arrow.right")
                            }
                            .tint(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if uncategorized.isEmpty {
                ContentUnavailableView(
                    "Inbox Clear",
                    systemImage: "checkmark.circle",
                    description: Text("All transactions are categorized.")
                )
            }
        }
        .premiumList()
        .navigationTitle("Inbox")
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .automatic) {
                    Button("Assign Category (\(selectedIDs.count))") {
                        showingBulkPicker = true
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Deselect All") {
                        selectedIDs.removeAll()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        let result = AutoCategorizer.categorizeAll(
                            transactions: uncategorized,
                            categories: categories,
                            rules: rules
                        )
                        lastAutoResult = result
                    } label: {
                        Label("Auto-Categorize All", systemImage: "sparkles")
                    }
                    .disabled(uncategorized.isEmpty)

                    Divider()

                    Button {
                        selectedIDs = Set(uncategorized.map(\.id))
                    } label: {
                        Label("Select All", systemImage: "checkmark.circle")
                    }
                    .disabled(uncategorized.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingBulkPicker) {
            BulkCategorySheet(
                categories: categories,
                count: selectedIDs.count
            ) { category in
                let selected = uncategorized.filter { selectedIDs.contains($0.id) }
                for txn in selected {
                    txn.category = category
                    RulesEngine.learnRule(from: txn, context: context)
                }
                selectedIDs.removeAll()
            }
        }
    }
}

struct BulkCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    let count: Int
    let onSelect: (Category) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Expense Categories") {
                    ForEach(categories.filter { !$0.isIncome }) { cat in
                        Button {
                            onSelect(cat)
                            dismiss()
                        } label: {
                            Label(cat.name, systemImage: cat.icon)
                                .foregroundStyle(Color(hex: cat.colorHex))
                        }
                    }
                }
                Section("Income Categories") {
                    ForEach(categories.filter { $0.isIncome }) { cat in
                        Button {
                            onSelect(cat)
                            dismiss()
                        } label: {
                            Label(cat.name, systemImage: cat.icon)
                                .foregroundStyle(Color(hex: cat.colorHex))
                        }
                    }
                }
            }
            .navigationTitle("Assign to \(count) Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .macOSSheet(width: 400, height: 500)
    }
}

struct InboxTransactionRow: View {
    let transaction: Transaction
    let categories: [Category]
    let rules: [CategoryRule]
    let context: ModelContext

    private var suggestion: CategorySuggestion? {
        AutoCategorizer.categorize(transaction: transaction, categories: categories, rules: rules)
    }

    private var relevantCategories: [Category] {
        categories.filter { $0.isIncome == transaction.isIncome }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let acc = transaction.account {
                        Text(acc.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let date = transaction.date as Date? {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let suggestion = suggestion {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(suggestion.category.name)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Apply") {
                            transaction.category = suggestion.category
                            RulesEngine.learnRule(from: transaction, context: context)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Spacer()

            Text(CurrencyFormatter.shared.format(transaction.amount, currency: transaction.account?.currency ?? "USD"))
                .font(.body.monospacedDigit())
                .foregroundStyle(transaction.isExpense ? .red : .green)

            categoryPicker
        }
        .padding(.vertical, 4)
    }

    private var categoryPicker: some View {
        Menu {
            if let suggestion = suggestion {
                Section("Suggested") {
                    Button {
                        transaction.category = suggestion.category
                        RulesEngine.learnRule(from: transaction, context: context)
                    } label: {
                        Label(suggestion.category.name, systemImage: suggestion.category.icon)
                    }
                }
                Divider()
            }

            Section("All Categories") {
                ForEach(relevantCategories) { cat in
                    Button {
                        transaction.category = cat
                        RulesEngine.learnRule(from: transaction, context: context)
                    } label: {
                        Label(cat.name, systemImage: cat.icon)
                    }
                }
            }
        } label: {
            Image(systemName: suggestion != nil ? "tag.circle.fill" : "tag.circle")
                .font(.title3)
                .foregroundStyle(suggestion != nil ? .orange : .secondary)
        }
    }
}
