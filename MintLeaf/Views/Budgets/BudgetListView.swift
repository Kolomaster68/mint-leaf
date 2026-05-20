import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @State private var showingNewBudget = false
    @State private var selectedBudget: Budget?
    @State private var editingBudget: Budget?
    @State private var budgetToDelete: Budget?

    var body: some View {
        if let selectedBudget {
            BudgetDetailView(budget: selectedBudget, onBack: { self.selectedBudget = nil })
        } else {
            budgetList
        }
    }

    private var budgetList: some View {
        List {
            ForEach(budgets) { budget in
                Button {
                    selectedBudget = budget
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(budget.name)
                                .font(.headline)
                            Spacer()
                            Text(budget.period.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        BudgetProgressBar(spent: budget.totalSpent, total: budget.totalBudgeted)
                        HStack {
                            Text(CurrencyFormatter.shared.format(budget.totalSpent) + " spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(budget.totalBudgeted) + " budgeted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        selectedBudget = budget
                    } label: {
                        Label("View Details", systemImage: "eye")
                    }
                    Button {
                        editingBudget = budget
                    } label: {
                        Label("Edit Budget", systemImage: "pencil")
                    }
                    Button {
                        duplicateBudget(budget)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        budgetToDelete = budget
                    } label: {
                        Label("Delete Budget", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        budgetToDelete = budget
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        editingBudget = budget
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .overlay {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "chart.pie",
                    description: Text("Create a budget to track your spending goals.")
                )
            }
        }
        .premiumList()
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewBudget = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewBudget) {
            NewBudgetSheet()
        }
        .sheet(item: $editingBudget) { budget in
            NewBudgetSheet(editing: budget)
        }
        .alert("Delete Budget?", isPresented: .init(
            get: { budgetToDelete != nil },
            set: { if !$0 { budgetToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { budgetToDelete = nil }
            Button("Delete", role: .destructive) {
                if let budget = budgetToDelete {
                    for item in budget.items {
                        context.delete(item)
                    }
                    context.delete(budget)
                    budgetToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete \"\(budgetToDelete?.name ?? "")\" and all its budget items. This cannot be undone.")
        }
    }

    private func duplicateBudget(_ source: Budget) {
        let newBudget = Budget(name: "\(source.name) Copy", period: source.period, startDate: source.startDate)
        context.insert(newBudget)
        for item in source.items {
            let newItem = BudgetItem(amount: item.amount, category: item.category, budget: newBudget)
            context.insert(newItem)
        }
    }
}

struct BudgetProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    let spent: Decimal
    let total: Decimal

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(truncating: (spent / total) as NSDecimalNumber), 1.5)
    }

    private var barFill: some ShapeStyle {
        if progress > 1.0 { return AnyShapeStyle(.red) }
        if progress > 0.8 { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(AppTheme.accentGradient(for: scheme))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.accent(for: scheme).opacity(0.12))
                Capsule()
                    .fill(barFill)
                    .frame(width: geo.size.width * min(progress, 1.0))
            }
        }
        .frame(height: 8)
    }
}
