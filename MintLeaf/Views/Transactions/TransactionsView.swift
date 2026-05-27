import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let account: Account
    @State private var searchText = ""
    @State private var showingNewTransaction = false
    @State private var showingImport = false
    @State private var selectedTransaction: Transaction?
    @State private var showingReconcile = false
    @State private var showingPDFImport = false
    @State private var showingExcelImport = false

    private var filteredTransactions: [Transaction] {
        let sorted = account.transactions.sorted { $0.date > $1.date }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            ($0.category?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var groupedByDate: [(String, [Transaction])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_GB")
        let grouped = Dictionary(grouping: filteredTransactions) { formatter.string(from: $0.date) }
        return grouped.sorted { lhs, rhs in
            guard let l = lhs.value.first?.date, let r = rhs.value.first?.date else { return false }
            return l > r
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            accountHeader
            transactionsList
        }
        .searchable(text: $searchText, prompt: "Search transactions")
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button(action: { showingImport = true }) {
                        Label("Import CSV", systemImage: "tablecells")
                    }
                    Button(action: { showingPDFImport = true }) {
                        Label("Import PDF Statement", systemImage: "doc.richtext")
                    }
                    Button(action: { showingExcelImport = true }) {
                        Label("Import Spreadsheet", systemImage: "tablecells.badge.ellipsis")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                Button(action: { showingReconcile = true }) {
                    Image(systemName: "checkmark.circle")
                }
                Button(action: { showingNewTransaction = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewTransaction) {
            EditTransactionSheet(account: account)
        }
        .sheet(item: $selectedTransaction) { transaction in
            EditTransactionSheet(account: account, transaction: transaction)
        }
        .sheet(isPresented: $showingImport) {
            CSVImportView(account: account)
        }
        .sheet(isPresented: $showingPDFImport) {
            PDFImportView(account: account)
        }
        .sheet(isPresented: $showingExcelImport) {
            ExcelImportView(account: account)
        }
        .sheet(isPresented: $showingReconcile) {
            ReconcileView(account: account)
        }
    }

    private var accountHeader: some View {
        VStack(spacing: 6) {
            Text("Current Balance")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.accent(for: scheme))
            Text(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(account.currentBalance >= 0 ? Color.primary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var transactionsList: some View {
        List {
            ForEach(groupedByDate, id: \.0) { dateString, transactions in
                Section(dateString) {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                            .contentShape(Rectangle())
                            #if os(macOS)
                            .onTapGesture(count: 2) { selectedTransaction = transaction }
                            #else
                            .onTapGesture { selectedTransaction = transaction }
                            #endif
                            .contextMenu {
                                Button {
                                    selectedTransaction = transaction
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    transaction.isReconciled.toggle()
                                } label: {
                                    Label(
                                        transaction.isReconciled ? "Unreconcile" : "Reconcile",
                                        systemImage: transaction.isReconciled ? "xmark.circle" : "checkmark.circle"
                                    )
                                }
                                if let category = transaction.category {
                                    Button {
                                        transaction.category = nil
                                    } label: {
                                        Label("Remove Category (\(category.name))", systemImage: "tag.slash")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    account.adjustBalance(by: -transaction.amount)
                                    context.delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    account.adjustBalance(by: -transaction.amount)
                                    context.delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    transaction.isReconciled.toggle()
                                } label: {
                                    Label(
                                        transaction.isReconciled ? "Unreconcile" : "Reconcile",
                                        systemImage: transaction.isReconciled ? "xmark.circle" : "checkmark.circle"
                                    )
                                }
                                .tint(.accentColor)
                            }
                    }
                }
            }
        }
        .premiumList()
    }
}
