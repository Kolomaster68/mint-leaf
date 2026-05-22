import SwiftUI
import SwiftData

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let budget: Budget
    var onBack: (() -> Void)? = nil
    @State private var showingAddItem = false
    @State private var editingItem: BudgetItem?
    @State private var itemToDelete: BudgetItem?

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Spent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(budget.totalSpent))
                            .font(.title3.bold())
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    VStack(alignment: .center) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(budget.totalBudgeted - budget.totalSpent))
                            .font(.title3.bold())
                            .foregroundStyle(budget.totalSpent <= budget.totalBudgeted ? AppTheme.accent(for: scheme) : .red)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Budget")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.shared.format(budget.totalBudgeted))
                            .font(.title3.bold())
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Categories") {
                ForEach(budget.items) { item in
                    VStack(spacing: 8) {
                        HStack {
                            if let cat = item.category {
                                Image(systemName: cat.icon)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                Text(cat.name)
                            } else {
                                Text("Uncategorized")
                            }
                            Spacer()
                            Text("\(CurrencyFormatter.shared.format(item.spent)) / \(CurrencyFormatter.shared.format(item.amount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        BudgetProgressBar(spent: item.spent, total: item.amount)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            editingItem = item
                        } label: {
                            Label("Edit Item", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            itemToDelete = item
                        } label: {
                            Label("Delete Item", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            itemToDelete = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingItem = item
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .premiumList()
        .navigationTitle(budget.name)
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .navigation) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddItem = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddBudgetItemSheet(budget: budget)
        }
        .sheet(item: $editingItem) { item in
            AddBudgetItemSheet(budget: budget, editing: item)
        }
        .alert("Delete Budget Item?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    context.delete(item)
                    itemToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete this budget item. This cannot be undone.")
        }
    }
}

struct AddBudgetItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    let budget: Budget
    var editing: BudgetItem?

    @State private var selectedCategory: Category?
    @State private var amount = ""

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $selectedCategory) {
                    Text("Select").tag(nil as Category?)
                    ForEach(categories.filter { !$0.isIncome }) { cat in
                        Label(cat.name, systemImage: cat.icon).tag(cat as Category?)
                    }
                }
                TextField("Budget Amount", text: $amount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .navigationTitle(isEditing ? "Edit Budget Item" : "Add Budget Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let value = Decimal(string: amount) {
                            if let editing {
                                editing.amount = value
                                editing.category = selectedCategory
                            } else {
                                let item = BudgetItem(amount: value, category: selectedCategory, budget: budget)
                                context.insert(item)
                            }
                            dismiss()
                        }
                    }
                    .disabled(amount.isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    selectedCategory = editing.category
                    amount = "\(editing.amount)"
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 500, height: 340)
    }
}
