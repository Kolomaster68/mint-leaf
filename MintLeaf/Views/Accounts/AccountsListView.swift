import SwiftUI
import SwiftData

struct AccountsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var showingNewAccount = false
    @State private var editingAccount: Account?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter { $0.isArchived } }

    private var totalBalance: Decimal {
        activeAccounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text("Total Balance")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accent(for: scheme))
                    Text(CurrencyFormatter.shared.format(totalBalance))
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Active Accounts") {
                ForEach(activeAccounts) { account in
                    NavigationLink {
                        TransactionsView(account: account)
                    } label: {
                        AccountRow(account: account)
                    }
                    .contextMenu {
                        Button {
                            editingAccount = account
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            account.isArchived = true
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) {
                            context.delete(account)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if !archivedAccounts.isEmpty {
                Section("Archived") {
                    ForEach(archivedAccounts) { account in
                        AccountRow(account: account)
                            .opacity(0.6)
                            .contextMenu {
                                Button {
                                    account.isArchived = false
                                } label: {
                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    context.delete(account)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .premiumList()
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewAccount = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            NewAccountSheet()
        }
        .sheet(item: $editingAccount) { account in
            NewAccountSheet(account: account)
        }
    }
}

struct AccountRow: View {
    @Environment(\.colorScheme) private var scheme
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.icon)
                .font(.title3)
                .foregroundStyle(Color(hex: account.colorHex))
                .frame(width: 32, height: 32)
                .background(Color(hex: account.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading) {
                Text(account.name)
                    .font(.body)
                Text(account.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(CurrencyFormatter.shared.format(account.currentBalance, currency: account.currency))
                .font(.body.monospacedDigit())
                .foregroundStyle(account.currentBalance >= 0 ? AppTheme.accent(for: scheme) : Color.red)
        }
        .padding(.vertical, 4)
    }
}
