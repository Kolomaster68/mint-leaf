import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var searchText = ""
    @State private var filterType: FilterType = .all
    @State private var selectedTransaction: Transaction?

    enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case income = "Income"
        case expenses = "Expenses"

        var id: String { rawValue }
    }

    private var filteredTransactions: [Transaction] {
        var results = allTransactions

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { txn in
                txn.title.lowercased().contains(query)
                || (txn.category?.name.lowercased().contains(query) ?? false)
                || (txn.account?.name.lowercased().contains(query) ?? false)
                || txn.notes.lowercased().contains(query)
                || CurrencyFormatter.shared.format(txn.amount).lowercased().contains(query)
            }
        }

        switch filterType {
        case .all: break
        case .income: results = results.filter { $0.isIncome }
        case .expenses: results = results.filter { $0.isExpense }
        }

        return results
    }

    private var resultTotal: Decimal {
        filteredTransactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    TextField("Search transactions, categories, accounts...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.accent(for: scheme).opacity(0.15), lineWidth: 1))

                Picker("", selection: $filterType) {
                    ForEach(FilterType.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Results summary
            if !searchText.isEmpty {
                HStack {
                    Text("\(filteredTransactions.count) result\(filteredTransactions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total: \(CurrencyFormatter.shared.format(resultTotal))")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(resultTotal >= 0 ? .green : .red)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Results list
            if searchText.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text("Search your transactions")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Search by name, category, account, notes, or amount")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if filteredTransactions.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No transactions match \"\(searchText)\"")
                )
                Spacer()
            } else {
                List {
                    ForEach(filteredTransactions.prefix(100)) { transaction in
                        TransactionRow(transaction: transaction, showAccount: true)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedTransaction = transaction }
                    }
                }
                .premiumList()
            }
        }
        .background(AppTheme.surfaceBackground(for: scheme))
        .navigationTitle("Search")
        .sheet(item: $selectedTransaction) { txn in
            if let account = txn.account {
                EditTransactionSheet(account: account, transaction: txn)
            }
        }
    }
}
