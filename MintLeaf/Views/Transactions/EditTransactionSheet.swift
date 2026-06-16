import SwiftUI
import SwiftData

struct EditTransactionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    let account: Account
    var transaction: Transaction?

    @State private var title = ""
    @State private var amount = ""
    @State private var isExpense = true
    @State private var date = Date()
    @State private var notes = ""
    @State private var selectedCategory: Category?
    @State private var isTransfer = false
    @State private var transferAccount: Account?
    @State private var selectedTags: Set<UUID> = []
    @State private var location = ""

    private var isEditing: Bool { transaction != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)

                    TextField("Payee", text: $title)
                    TextField("Amount", text: $amount)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    let filtered = categories.filter { $0.isIncome == !isExpense }
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Category?)
                        ForEach(filtered) { cat in
                            Label(cat.name, systemImage: cat.icon).tag(cat as Category?)
                        }
                    }
                }

                Section {
                    Toggle("Transfer to another account", isOn: $isTransfer)
                    if isTransfer {
                        Picker("Destination", selection: $transferAccount) {
                            Text("Select account").tag(nil as Account?)
                            ForEach(accounts.filter { $0.id != account.id }) { acc in
                                Text(acc.name).tag(acc as Account?)
                            }
                        }
                    }
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Location (optional)", text: $location)
                    }
                }

                if !allTags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags) { tag in
                                let isSelected = selectedTags.contains(tag.id)
                                Button {
                                    if isSelected {
                                        selectedTags.remove(tag.id)
                                    } else {
                                        selectedTags.insert(tag.id)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "tag.fill")
                                            .font(.caption2)
                                        Text(tag.name)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isSelected
                                            ? Color(hex: tag.colorHex).opacity(0.2)
                                            : Color.secondary.opacity(0.1),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            isSelected ? Color(hex: tag.colorHex) : Color.clear,
                                            lineWidth: 1.5
                                        )
                                    )
                                    .foregroundStyle(isSelected ? Color(hex: tag.colorHex) : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete Transaction", role: .destructive) {
                            if let transaction {
                                TransferService.delete(transaction, context: context)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(title.isEmpty || amount.isEmpty)
                }
            }
            .onAppear(perform: loadTransaction)
        }
        .formStyle(.grouped)
        .macOSSheet(width: 580, height: 520)
    }

    private func loadTransaction() {
        guard let t = transaction else { return }
        title = t.title
        amount = "\(t.absoluteAmount)"
        isExpense = t.isExpense
        date = t.date
        notes = t.notes
        location = t.location ?? ""
        selectedCategory = t.category
        selectedTags = Set(t.tags.map(\.id))
        if let dest = t.transferDestination {
            isTransfer = true
            transferAccount = dest
        }
    }

    private func save() {
        guard let value = Decimal(string: amount) else { return }
        let signedAmount = isExpense ? -abs(value) : abs(value)

        let tagsToApply = allTags.filter { selectedTags.contains($0.id) }

        // A transfer to the same account makes no sense — treat it as a normal transaction.
        let newDest: Account? = (isTransfer && transferAccount?.id != account.id) ? transferAccount : nil

        if let t = transaction {
            let oldAmount = t.amount
            let oldMirror = TransferService.findMirror(of: t)
            let oldDest = t.transferDestination

            t.title = title
            t.amount = signedAmount
            t.date = date
            t.notes = notes
            t.location = location.isEmpty ? nil : location
            t.category = selectedCategory
            t.tags = tagsToApply
            t.transferDestination = newDest
            account.adjustBalance(by: signedAmount - oldAmount)

            if let newDest {
                let pairID = t.transferPairID ?? UUID()
                t.transferPairID = pairID
                let mirrorNote = "Transfer \(isExpense ? "to" : "from") \(account.name)"

                if let oldMirror, oldDest?.id == newDest.id {
                    // Same destination — update the existing mirror in place.
                    let oldMirrorAmount = oldMirror.amount
                    oldMirror.transferPairID = pairID
                    oldMirror.amount = -signedAmount
                    oldMirror.title = title
                    oldMirror.date = date
                    oldMirror.notes = mirrorNote
                    newDest.adjustBalance(by: -signedAmount - oldMirrorAmount)
                } else {
                    // Destination changed (or there was no mirror) — remove the old, add a fresh one.
                    if let oldMirror, let acc = oldMirror.account {
                        acc.adjustBalance(by: -oldMirror.amount)
                        context.delete(oldMirror)
                    }
                    let mirror = Transaction(amount: -signedAmount, title: title, date: date,
                                             notes: mirrorNote, category: selectedCategory, account: newDest)
                    mirror.transferDestination = account
                    mirror.transferPairID = pairID
                    context.insert(mirror)
                    newDest.adjustBalance(by: -signedAmount)
                }
            } else {
                // No longer a transfer — remove any existing mirror and reverse its effect.
                if let oldMirror, let acc = oldMirror.account {
                    acc.adjustBalance(by: -oldMirror.amount)
                    context.delete(oldMirror)
                }
                t.transferPairID = nil
            }
        } else {
            let t = Transaction(
                amount: signedAmount,
                title: title,
                date: date,
                notes: notes,
                category: selectedCategory,
                account: account
            )
            t.location = location.isEmpty ? nil : location
            t.transferDestination = newDest
            t.tags = tagsToApply
            context.insert(t)
            account.adjustBalance(by: signedAmount)

            if let dest = newDest {
                let pairID = UUID()
                t.transferPairID = pairID
                let mirror = Transaction(
                    amount: -signedAmount,
                    title: title,
                    date: date,
                    notes: "Transfer \(isExpense ? "to" : "from") \(account.name)",
                    category: selectedCategory,
                    account: dest
                )
                mirror.transferDestination = account
                mirror.transferPairID = pairID
                context.insert(mirror)
                dest.adjustBalance(by: -signedAmount)
            }
        }
        dismiss()
    }
}
