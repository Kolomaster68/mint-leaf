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

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reordered = activeAccounts
        reordered.move(fromOffsets: source, toOffset: destination)
        // Reassign sortOrder so the new order persists. Archived accounts keep
        // higher numbers so they never interleave with active ones.
        for (index, account) in reordered.enumerated() {
            account.sortOrder = index
        }
        for (offset, account) in archivedAccounts.enumerated() {
            account.sortOrder = reordered.count + offset
        }
        try? context.save()
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

            Section {
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
                .onMove(perform: moveAccounts)
            } header: {
                Text("Active Accounts")
            } footer: {
                if activeAccounts.count > 1 {
                    Text("Drag to reorder your accounts.")
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
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                if activeAccounts.count > 1 {
                    EditButton()
                }
            }
            #endif
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
        VStack(spacing: 8) {
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

            if account.hasOverdraft && account.isOverdrawn {
                overdraftBar
            }
        }
        .padding(.vertical, 4)
    }

    private var overdraftBar: some View {
        let overLimit = account.isOverArrangedLimit
        let usageColor: Color = overLimit ? AppTheme.expense
            : account.overdraftUsageFraction > 0.8 ? AppTheme.warning
            : AppTheme.accent(for: scheme)

        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(usageColor)
                        .frame(width: geo.size.width * min(1, account.overdraftUsageFraction))
                }
            }
            .frame(height: 5)

            HStack {
                Text(overLimit
                     ? "Over your \(CurrencyFormatter.shared.format(account.overdraftLimit ?? 0, currency: account.currency)) overdraft"
                     : "Using \(CurrencyFormatter.shared.format(account.overdraftUsed, currency: account.currency)) of \(CurrencyFormatter.shared.format(account.overdraftLimit ?? 0, currency: account.currency)) overdraft")
                    .foregroundStyle(overLimit ? AppTheme.expense : .secondary)
                Spacer()
                Text("\(CurrencyFormatter.shared.format(account.availableToSpend, currency: account.currency)) available")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.leading, 44)
    }
}
