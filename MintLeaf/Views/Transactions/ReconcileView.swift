import SwiftUI

struct ReconcileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let account: Account
    @State private var statementBalance = ""
    @State private var statementDate = Date()
    @State private var checkedTransactions: Set<String> = []

    private var unreconciledTransactions: [Transaction] {
        account.transactions
            .filter { !$0.isReconciled }
            .sorted { $0.date > $1.date }
    }

    private var checkedBalance: Decimal {
        let reconciledBase = account.initialBalance + account.transactions
            .filter { $0.isReconciled }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return reconciledBase + unreconciledTransactions
            .filter { checkedTransactions.contains($0.id.uuidString) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var difference: Decimal {
        let target = Decimal(string: statementBalance) ?? 0
        return target - checkedBalance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Statement") {
                    DatePicker("Date", selection: $statementDate, displayedComponents: .date)
                    TextField("Balance", text: $statementBalance)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    HStack {
                        Text("Difference")
                        Spacer()
                        Text(CurrencyFormatter.shared.format(difference))
                            .foregroundStyle(difference == 0 ? .green : .red)
                            .bold()
                    }
                }

                Section("Unreconciled (\(unreconciledTransactions.count))") {
                    if unreconciledTransactions.isEmpty {
                        Text("All transactions reconciled")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unreconciledTransactions) { transaction in
                            HStack(spacing: 10) {
                                Button {
                                    let id = transaction.id.uuidString
                                    if checkedTransactions.contains(id) {
                                        checkedTransactions.remove(id)
                                    } else {
                                        checkedTransactions.insert(id)
                                    }
                                } label: {
                                    Image(systemName: checkedTransactions.contains(transaction.id.uuidString) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checkedTransactions.contains(transaction.id.uuidString) ? AppTheme.accent(for: scheme) : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(transaction.title)
                                    .lineLimit(1)

                                Spacer()

                                Text(CurrencyFormatter.shared.format(transaction.amount))
                                    .monospacedDigit()
                                    .foregroundStyle(transaction.amount < 0 ? .red : .green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reconcile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        for txn in unreconciledTransactions where checkedTransactions.contains(txn.id.uuidString) {
                            txn.isReconciled = true
                        }
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .macOSSheet(width: 600, height: 550)
    }
}
